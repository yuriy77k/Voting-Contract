# Voting-Contract
Allows users to create proposal and Stakers may vote for it.

This contract is compatible with a current version of Cold Staking contract (address 0xd813419749b3c2cDc94A2F9Cfcf154113264a9d6).
Stakers may vote using voting DAPP or directly from any wallet, even without supporting voting DAPP.

## Description

Voting is the main contract to deploy. It creates the Ballot of a proposal, stores proposals and voting results.

To create a proposal, anybody can send a set amount of CLO to functions `createProposal` or `createProposalFull`. It creates new Ballot contract for that proposal. Stakers may vote via function `voting` or just send 0 CLO with selected option number (01-04) in Data field to the Ballot contract.

After vote finishing user should call `refundPayment` to refund payment and update proposal voting results.

Ballot contract could be destroyed when one year passed after the end of a vote.

For convinient monitoring contrat generate two events:

`CreateProposal` with fields:
* address of Ballot contract for proposal.
* name of proposal.
* url with proposal and options description. 

`WinProposal` with those and additional fields:
* winnerOption - the option with the most votes. 
* winnerPercent - percentage of votes for the winning option of all those who voted.
* quorumPercent - percentage of total numbers of voters took who took part in voting (is a quorum or isn't).
