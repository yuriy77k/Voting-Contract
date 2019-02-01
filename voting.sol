pragma solidity ^0.5.1;

// Contains global constants which may be used in Voting and Ballot contracts.
contract GlobalConstants {
    // Cold Staking contract address. Only Stakers can vote.
    address constant COLD_STAKING_ADDRESS = 0xd813419749b3c2cDc94A2F9Cfcf154113264a9d6;
    // Maximum number of options on the ballot.
    uint constant MAX_NUM_OPTIONS = 4;
}

// Voting is the main contract to deploy. It creates the Ballot of a proposal, stores proposals and voting results.
contract Voting is GlobalConstants {

    struct Proposal
    {
        string name;
        string url;
        bytes32 hash;
        uint startTime;
        uint endTime;
        uint8 numOptions; // The number of options to select on the vote (maximum 4).
        bool timeRestriction;
        bool canChangeVote;
        bool destructable;
        uint[MAX_NUM_OPTIONS+1] votes; // Votes for options.
        uint totalAvailableVotes; // All available votes (total staked amount on the beginning of voting).
    }

    mapping (address => Proposal) public proposals;

    struct Payment
    {
        address payable payer;
        uint amount;
    }

    mapping (address => Payment) payments; 
    // Owner address (Callisto Staking Reserve address). The owner can change proposalThreshold only.
    address owner = 0x3c06f218Ce6dD8E2c535a8925A2eDF81674984D9;
    // The amount of funds that will be held by voting contract during the proposal consideration/voting. Owner can change it.
    uint public proposalThreshold = 1000 ether;
    // A total number of created proposals.
    uint public numProposals;

    // Default values:
    // Voting duration.
    uint constant VOTING_DURATION = 10 days;
    // Disallow Staker to vote if staked time greater then voting start time. It protects from double voting when Staker withdraws and stake again from another address.
    bool constant TIME_RESTRICTION = true;
    // The voter can change mind if he did not touch his stake.
    bool constant CAN_CHANGE_VOTE = true;
    // Allow to anybody destroy Ballot contract to free blockchain memory when one year passed after finish voting.
    bool constant DESTRUCTABLE = true;
  
    event CreateProposal(address indexed ballot, string name, string url);
    // Percent of total numbers of voters took part in voting. Need to know is a quorum or isn't.
    event WinProposal(address indexed ballot, string name, string url, uint8 winnerOption, uint8 percentTotalVoters);

    // The only function which requires to be an owner.
    function changeThreshold (uint _proposalThreshold) public {
        require(msg.sender == owner);
        proposalThreshold = _proposalThreshold;
    }

    // Create a proposal with default values of votingDuration, timeRestriction, canChangeVote, destructable.
    function createProposal(
        string memory _name,
        string memory _url,
        bytes32 _hash,
        uint _startTime,
        uint8 _numOptions
    ) public payable returns (address) {
        return createProposalFull(_name,_url,_hash,_startTime,VOTING_DURATION,_numOptions,TIME_RESTRICTION,CAN_CHANGE_VOTE,DESTRUCTABLE);
    }

    // Create a proposal with all parameters.
    function createProposalFull(
        string memory _name,
        string memory _url,
        bytes32 _hash,
        uint _startTime,
        uint _duration,
        uint8 _numOptions,
        bool _timeRestriction,
        bool _canChangeVote,
        bool _destructable
    ) public payable returns (address _ballot) {
        require(_numOptions > 0 && _numOptions <= MAX_NUM_OPTIONS, "Incorrect number of options.");
        require(now < _startTime && now + 365 days > _startTime, "Incorrect start time");
        require(_duration >= 1 days && _duration <= 90 days, "Incorrect duration");

        // Check a proposal payment threshold.
        require (msg.value >= proposalThreshold, "Insufficient payment amount.");

        // Increase proposals counter.
        numProposals++;

        // Store proposal into proposals list.
        Proposal memory p;
        p.name = _name;
        p.url = _url;
        p.hash = _hash;
        p.startTime = _startTime;
        p.endTime = _startTime + _duration;
        p.numOptions = _numOptions;
        p.timeRestriction = _timeRestriction;
        p.canChangeVote = _canChangeVote;
        p.destructable = _destructable;

        // Create a ballot for the proposal.
        _ballot = address(new Ballot(_name,_url,_hash,_startTime,p.endTime,_numOptions,_timeRestriction,_canChangeVote,_destructable));
        proposals[_ballot] = p;

        // Save payment to refund after the end of votе.
        payments[_ballot].payer = msg.sender;
        payments[_ballot].amount = msg.value;

        emit CreateProposal(_ballot,_name,_url);
    }
    
    // After vote finishing refund payment to creator and update proposal voting results.
    function refundPayment(address _ballot) public returns (uint _winner, uint _percent) {
        require(now > proposals[_ballot].endTime, "Voting is not finished, try later.");
        require(payments[_ballot].amount > 0, "Payment already refunded.");

        // Copy voting results from ballot contract.
        Ballot b = Ballot(_ballot);
        uint _max;
        uint _sum;
        for (uint i = 1; i <= MAX_NUM_OPTIONS; i++)
        {
            proposals[_ballot].votes[i] = b.votes(i);
            _sum += proposals[_ballot].votes[i];
            if (proposals[_ballot].votes[i] > _max) {
                _max = proposals[_ballot].votes[i];
                _winner = i;
            }
        }
        proposals[_ballot].totalAvailableVotes = b.totalAvailableVotes();

        // Percent of total numbers of voters took part in voting. Need to know is a quorum or isn't.
        _percent = _sum * 100 / proposals[_ballot].totalAvailableVotes;

        // Refund paymnet to proposal creator.
        uint _amount = payments[_ballot].amount;
        address payable _payer = payments[_ballot].payer;
        delete payments[_ballot];
        _payer.transfer(_amount);

        emit WinProposal(_ballot,proposals[_ballot].name,proposals[_ballot].url,uint8(_winner),uint8(_percent));
    }

    // Vote on selected ballot.
    function voting(address _ballot, uint8 _selection) public {
        Ballot b = Ballot(_ballot);
        b.voting(_selection);
    }

    // View votes for selected proposal option.
    function proposalVotes(address _ballot, uint8 _selection) public view returns(uint _votes) {
        _votes = proposals[_ballot].votes[_selection];
    }
} 

// Ballot contract creates by the Voting contract and allows Stakers to vote for propose.
contract Ballot is GlobalConstants {
    
    using SafeMath for uint;
    struct Proposal
    {
        string name;
        string url;
        bytes32 hash;
        uint startTime;
        uint endTime;
        uint8 numOptions;
        bool timeRestriction;
        bool canChangeVote;
        bool destructable;
    }
    Proposal public proposal;

    mapping (address => uint8) public voter;
    uint[MAX_NUM_OPTIONS+1] public votes;   // Votes for options.
    uint public numVoters; // The number of voters-addresses (not votes).
    uint public totalAvailableVotes; // All available votes (total staked amount on the beginning of voting).
    address owner;  // Address of contract creator (Voting contract address).

    ColdStaking public coldStaking = ColdStaking(COLD_STAKING_ADDRESS); // Cold Staking contract address.

    constructor (
        string memory _name,
        string memory _url,
        bytes32 _hash,
        uint _startTime,
        uint _endTime,
        uint8 _numOptions,
        bool _timeRestriction,
        bool _canChangeVote,
        bool _destructable
    ) public {
        require(_numOptions > 0 && _numOptions <= MAX_NUM_OPTIONS);
        owner = msg.sender;
        proposal.name = _name;
        proposal.url = _url;
        proposal.hash = _hash;
        proposal.startTime = _startTime;
        proposal.endTime = _endTime;
        proposal.numOptions = _numOptions;
        proposal.timeRestriction = _timeRestriction;
        proposal.canChangeVote = _canChangeVote;
        proposal.destructable = _destructable;
    }

    // Allow voting from any wallet, sending 0 CLO and setting data to option number (01-04).
    function () external {
        require (msg.data.length == 1, "Wrong choice of option.");
        voting(uint8(msg.data[0]));
    }

    function voting(uint8 _selection) public {
        require (_selection > 0 && _selection <= proposal.numOptions, "Wrong choice of option.");
        require (now >= proposal.startTime && now <= proposal.endTime, "Voting closed.");
        // Stakers could vote via Voting contract too.
        address _sender = (owner == msg.sender) ? tx.origin : msg.sender;
        (uint _amount, uint _time) = coldStaking.staker(_sender);
        require (_amount > 0, "You have to be Staker to vote.");
        // Get Total Staking Amount on begin of voting which is equal to total available votes.
        if (totalAvailableVotes == 0) {
            totalAvailableVotes = coldStaking.TotalStakingAmount();
        }
        // Disallow Staker to vote if staked time greater then voting start time. 
        // It protects from double voting when Staker withdraws and stake again from another address.
        if (proposal.timeRestriction) {
            require(_time < proposal.startTime, "Staked time after starting vote.");
        }

        // Staked amount = votes.
        if (voter[_sender] == 0) {
            voter[_sender] = _selection;
            votes[_selection] = votes[_selection].add(_amount);
            // Increase voters counter.
            numVoters++;
        } 
        // The voter can change mind if he did not touch his stake.
        else if (proposal.canChangeVote && _time >= proposal.startTime) {
            votes[voter[_sender]] = votes[_selection].sub(_amount);
            voter[_sender] = _selection;
            votes[_selection] = votes[_selection].add(_amount);
        }
    }

    // Anybody could destroy contract to free blockchain memory when one year passed after finish voting (if allowed).
    function destroy() external {
        require(proposal.destructable && now > proposal.endTime + 365 days);
        selfdestruct(address(0));
    }
}

contract ColdStaking {
    
    struct Staker
    {
        uint amount;
        uint time;
    }
    mapping (address => Staker) public staker;
    uint public TotalStakingAmount; //currently frozen amount for Staking.
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
 
library SafeMath {
  function mul(uint a, uint b) internal pure returns (uint) {
    if (a == 0) {
      return 0;
    }
    uint c = a * b;
    require(c / a == b);
    return c;
  }

  function div(uint a, uint b) internal pure returns (uint) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint a, uint b) internal pure returns (uint) {
    require(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    require(c >= a);
    return c;
  }
}
