;; CityCoins Vote V2
;;
;; A voting mechanism inspired by SIP-012 for Stacks,
;; defined in CCIP-011 and used to vote on ratifying
;; CCIP-012.
;;
;; This contract combines the functionality of the
;; original vote contract directly with the tardis
;; to reduce the number of external calls required.
;;
;; External Link: https://github.com/citycoins/governance

;; ERRORS

(define-constant ERR_PROPOSAL_NOT_FOUND (err u8002))
(define-constant ERR_PROPOSAL_NOT_ACTIVE (err u8003))
(define-constant ERR_VOTE_ALREADY_CAST (err u8004))
(define-constant ERR_NOTHING_STACKED (err u8005))
(define-constant ERR_CONTRACT_NOT_INITIALIZED (err u8006))
(define-constant ERR_UNAUTHORIZED (err u8007))

;; CONSTANTS

(define-constant DEPLOYER tx-sender)
(define-constant VOTE_PROPOSAL_ID u0)
(define-constant VOTE_SCALE_FACTOR (pow u10 u16)) ;; 16 decimal places
(define-constant MIA_SCALE_BASE (pow u10 u4)) ;; 4 decimal places
(define-constant MIA_SCALE_FACTOR u8605) ;; 0.8605 or 86.05%
;; MIA votes scaled to make 1 MIA = 1 NYC
;; full calculation available in CCIP-012

;; VARIABLES

(define-data-var initialized bool false)
(define-data-var voteStartBlock uint u0)
(define-data-var voteEndBlock uint u0)

;; PROPOSALS

(define-constant CCIP_012 {
  name: "Stabilize Emissions and Treasuries",
  link: "https://github.com/citycoins/governance/blob/main/ccips/ccip-012/ccip-012-stabilize-emissions-and-treasuries.md",
  hash: "a029edb4e00571ce497862d4c7ab484c62f41905"
})

(define-map ProposalVotes
  uint ;; proposalId
  {
    yesCount: uint,
    yesTotal: uint,
    noCount: uint,
    noTotal: uint
  }
)

;; intialize ProposalVotes
(map-insert ProposalVotes VOTE_PROPOSAL_ID {
  yesCount: u0,
  yesTotal: u0,
  noCount: u0,
  noTotal: u0
})

;; VOTERS

(define-data-var voterIndex uint u0)

(define-map Voters
  uint
  principal
)

(define-map VoterIds
  principal
  uint
)

(define-map Votes
  uint ;; voter ID
  {
    vote: bool,
    total: uint
  }
)

;; obtains the voter ID or creates a new one
(define-private (get-or-create-voter-id (user principal))
  (match (map-get? VoterIds user) value
    value
    (let
      (
        (newId (+ u1 (var-get voterIndex)))
      )
      (map-set Voters newId user)
      (map-set VoterIds user newId)
      (var-set voterIndex newId)
      newId
    )
  )
)

;; UTILITIES

;; one-time function to set the start and end
;; block heights for voting
(define-public (initialize-contract (startHeight uint) (endHeight uint))
  (begin
    (asserts! (not (is-initialized)) ERR_UNAUTHORIZED)
    (asserts! (is-deployer) ERR_UNAUTHORIZED)
    (asserts! (and
      (< block-height startHeight)
      (< startHeight endHeight))
      ERR_UNAUTHORIZED
    )
    (var-set voteStartBlock startHeight)
    (var-set voteEndBlock endHeight)
    (var-set initialized true)
    (ok true)
  )
)

;; get block hash by height
(define-private (get-block-hash (blockHeight uint))
  (get-block-info? id-header-hash blockHeight)
)

;; VOTE FUNCTIONS

(define-public (vote-on-proposal (vote bool))
  (let
    (
      (voterId (get-or-create-voter-id tx-sender))
      (voterRecord (map-get? Votes voterId))
      (proposalRecord (unwrap! (get-proposal-votes) ERR_PROPOSAL_NOT_FOUND))
    )
    ;; assert proposal is active
    (asserts! (is-initialized) ERR_CONTRACT_NOT_INITIALIZED)
    (asserts! (and
      (>= block-height (var-get voteStartBlock))
      (<= block-height (var-get voteEndBlock)))
      ERR_PROPOSAL_NOT_ACTIVE)
    ;; determine if vote record exists already
    (match voterRecord record
      ;; vote record exists
      (begin
        ;; check if vote is the same as what's recorded
        (asserts! (not (is-eq (get vote record) vote)) ERR_VOTE_ALREADY_CAST)
        ;; record the new vote
        (map-set Votes voterId
          (merge record { vote: vote })
        )
        ;; update the vote totals
        (if vote
          (map-set ProposalVotes VOTE_PROPOSAL_ID
            (merge proposalRecord {
              yesCount: (+ (get yesCount proposalRecord) u1),
              yesTotal: (+ (get yesTotal proposalRecord) (get total record)),
              noCount: (- (get noCount proposalRecord) u1),
              noTotal: (- (get noTotal proposalRecord) (get total record))
            })
          )
          (map-set ProposalVotes VOTE_PROPOSAL_ID
            (merge proposalRecord {
              yesCount: (- (get yesCount proposalRecord) u1),
              yesTotal: (- (get yesTotal proposalRecord) (get total record)),
              noCount: (+ (get noCount proposalRecord) u1),
              noTotal: (+ (get noTotal proposalRecord) (get total record))
            })
          )
        )
      )
      ;; vote record doesn't exist
      (let
        (
          (scaledVoteMia (default-to u0 (get-mia-vote tx-sender true)))
          (scaledVoteNyc (default-to u0 (get-nyc-vote tx-sender true)))
          (voteMia (scale-down scaledVoteMia))
          (voteNyc (scale-down scaledVoteNyc))
          (voteTotal (+ voteMia voteNyc))
        )
        ;; make sure there is a positive value
        (asserts! (or (> scaledVoteMia u0) (> scaledVoteNyc u0)) ERR_NOTHING_STACKED)
        ;; update the voter record
        (map-insert Votes voterId {
          vote: vote,
          total: voteTotal
        })
        ;; update the proposal record
        (if vote
          (map-set ProposalVotes VOTE_PROPOSAL_ID
            (merge proposalRecord {
              yesCount: (+ (get yesCount proposalRecord) u1),
              yesTotal: (+ (get yesTotal proposalRecord) voteTotal),
            })
          )
          (map-set ProposalVotes VOTE_PROPOSAL_ID
            (merge proposalRecord {
              noCount: (+ (get noCount proposalRecord) u1),
              noTotal: (+ (get noTotal proposalRecord) voteTotal)
            })
          )
        )
      )
    )
    (print (map-get? ProposalVotes VOTE_PROPOSAL_ID))
    (print (map-get? Votes voterId))
    (ok true)
  )
)

;; MIA vote calculation
;; returns (some uint) or (none)
;; optionally scaled by VOTE_SCALE_FACTOR (10^6)
(define-read-only (get-mia-vote (user principal) (scaled bool))
  (let
    (
      (userId (default-to u0 (contract-call? .citycoin-core-v1 get-user-id user)))
      ;; MIA cycle 21 / first block 68,597, cycle 2 / u4500 used in tests
      ;; mainnet: 'SP1H1733V5MZ3SZ9XRW9FKYGEZT0JDGEB8Y634C7R.miamicoin-core-v2
      (cycle21Hash (unwrap! (get-block-hash u4500) none))
      (cycle21Data (at-block cycle21Hash (contract-call? .citycoin-core-v1 get-stacker-at-cycle-or-default u2 userId)))
      (cycle21Amount (get amountStacked cycle21Data))
      ;; MIA cycle 22 / first block 70,697, cycle 3 / u6600 used in tests
      ;; mainnet: 'SP1H1733V5MZ3SZ9XRW9FKYGEZT0JDGEB8Y634C7R.miamicoin-core-v2
      (cycle22Hash (unwrap! (get-block-hash u6600) none))
      (cycle22Data (at-block cycle22Hash (contract-call? .citycoin-core-v1 get-stacker-at-cycle-or-default u3 userId)))
      (cycle22Amount (get amountStacked cycle22Data))
      ;; MIA vote calculation
      (avgStacked (/ (+ (scale-up cycle21Amount) (scale-up cycle22Amount)) u2))
      (scaledVote (/ (* avgStacked MIA_SCALE_FACTOR) MIA_SCALE_BASE))
    )
    ;; check for a positive value
    (asserts! (or (> cycle21Amount u0) (> cycle22Amount u0)) none)
    ;; return the value
    (if scaled
      (some scaledVote)
      (some (/ scaledVote VOTE_SCALE_FACTOR))
    )
  )
)

;; NYC vote calculation
;; returns (some uint) or (none)
;; optionally scaled by VOTE_SCALE_FACTOR (10^6)
(define-read-only (get-nyc-vote (user principal) (scaled bool))
  (let
    (
      (userId (default-to u0 (contract-call? .citycoin-core-v1 get-user-id user)))
      ;; NYC cycle 15 / first block 68,949, cycle 2 / u4500 used in tests
      ;; mainnet: 'SPSCWDV3RKV5ZRN1FQD84YE1NQFEDJ9R1F4DYQ11.newyorkcitycoin-core-v2
      (cycle15Hash (unwrap! (get-block-hash u4500) none))
      (cycle15Data (at-block cycle15Hash (contract-call? .citycoin-core-v1 get-stacker-at-cycle-or-default u2 userId)))
      (cycle15Amount (get amountStacked cycle15Data))
      ;; NYC cycle 16 / first block 71,049, cycle 3 / u6600 used in tests
      ;; mainnet: 'SPSCWDV3RKV5ZRN1FQD84YE1NQFEDJ9R1F4DYQ11.newyorkcitycoin-core-v2
      (cycle16Hash (unwrap! (get-block-hash u6600) none))
      (cycle16Data (at-block cycle16Hash (contract-call? .citycoin-core-v1 get-stacker-at-cycle-or-default u3 userId)))
      (cycle16Amount (get amountStacked cycle16Data))
      ;; NYC vote calculation
      (scaledVote (/ (+ (scale-up cycle15Amount) (scale-up cycle16Amount)) u2))
    )
    ;; check for a positive value
    (asserts! (or (> cycle15Amount u0) (> cycle16Amount u0)) none)
    ;; return the value
    (if scaled
      (some scaledVote)
      (some (/ scaledVote VOTE_SCALE_FACTOR))
    )
  )
)

;; GETTERS

;; returns if the start/end block heights are set
(define-read-only (is-initialized)
  (var-get initialized)
)

;; returns the list of proposals being voted on
(define-read-only (get-proposals)
  (some CCIP_012)
)

;; returns the start/end block heights, if set
(define-read-only (get-vote-blocks)
  (if (is-initialized)
    (some {
      startBlock: (var-get voteStartBlock),
      endBlock: (var-get voteEndBlock)
    })
    none
  )
)

;; returns the vote totals for the proposal
(define-read-only (get-proposal-votes)
  (map-get? ProposalVotes VOTE_PROPOSAL_ID)
)

;; returns the voter index for assigning voter IDs
(define-read-only (get-voter-index)
  (var-get voterIndex)
)

;; returns the voter principal for a given voter ID
(define-read-only (get-voter (voterId uint))
  (map-get? Voters voterId)
)

;; returns the voter ID for a given principal
(define-read-only (get-voter-id (voter principal))
  (map-get? VoterIds voter)
)

;; returns the vote totals for a given principal
(define-read-only (get-voter-info (voter principal))
  (let
    (
      (voterId (default-to u0 (get-voter-id voter)))
    )
    (asserts! (> voterId u0) none)
    (map-get? Votes voterId)
  )
)

;; UTILITIES
;; CREDIT: math functions taken from Alex math-fixed-point-16.clar

(define-private (scale-up (a uint))
  (* a VOTE_SCALE_FACTOR)
)

(define-private (scale-down (a uint))
  (/ a VOTE_SCALE_FACTOR)
)

(define-private (is-deployer)
  (is-eq contract-caller DEPLOYER)
)
