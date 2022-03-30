import { Account, ReadOnlyFn, Tx, types } from "../deps.ts";
import { Model } from "../src/model.ts";

enum ErrCode {
  ERR_USER_NOT_FOUND = 8000,
  ERR_STACKER_NOT_FOUND,
  ERR_PROPOSAL_NOT_FOUND,
  ERR_PROPOSAL_NOT_ACTIVE,
  ERR_VOTE_ALREADY_CAST,
  ERR_NOTHING_STACKED,
}

export class VoteModel extends Model {
  name = "citycoin-vote-v1";
  static readonly ErrCode = ErrCode;
  static readonly VOTE_START_BLOCK = 6500;
  static readonly VOTE_END_BLOCK = 8500;
  static readonly VOTE_PROPOSAL_ID = 0;
  static readonly VOTE_SCALE_FACTOR = 10 ** 16; // 16 decimal places
  static readonly MIA_SCALE_FACTOR = 0.6987; // 0.6987 or 69.87%

  voteOnProposal(vote: boolean, sender: Account): Tx {
    return this.callPublic(
      "vote-on-proposal",
      [types.bool(vote)],
      sender.address
    );
  }

  getVoteAmount(voter: Account): ReadOnlyFn {
    return this.callReadOnly("get-vote-amount", [types.principal(voter.address)]);
  }

  getProposalVotes(): ReadOnlyFn {
    return this.callReadOnly("get-proposal-votes");
  }

  getVoter(voterId: number): ReadOnlyFn {
    return this.callReadOnly("get-voter", [types.uint(voterId)]);
  }

  getVoterId(voter: Account): ReadOnlyFn { 
    return this.callReadOnly("get-voter-id", [types.principal(voter.address)]);
  }

  getVoterInfo(voter: Account): ReadOnlyFn {
    return this.callReadOnly("get-voter-info", [types.principal(voter.address)]);
  }
}