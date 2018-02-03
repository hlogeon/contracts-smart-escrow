pragma solidity ^0.4.13;

import "zeppelin-solidity/contracts/payment/PullPayment.sol";
import "zeppelin-solidity/contracts/ReentrancyGuard.sol";
import "zeppelin-solidity/contracts/token/ERC20Basic.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";

contract Escrow is PullPayment, ReentrancyGuard, Ownable {

    struct Round {
      uint8 number;
      string reason;
      string message;
      uint ETHAmount; // The value of ETH in current round
      uint minTokens; // Minimal amount of tokens required to vote
      uint8 positivePercent; // Percent of votes required to succeed
      uint startAfter;
      uint endAfter;
      uint startedAt;
      uint finishedAt;
      uint positive;
      uint negative;
      bool result;
      mapping (address => uint) votes; //Votes history
      mapping (address => uint) refunds;
    }

    enum RoundState { Waiting, Approval, Active, Paused }

    event InitRound(uint8 round, uint amount, string reason, string message);
    event Approved(address by, uint8 round, uint amount, uint timestamp);
    event Rejected(address by, uint8 round, uint amount, uint timestamp);
    event Vote(address voter, uint8 round, uint tokens, bool value);
    event RoundStarted(uint8 round, uint amount, uint timestamp);
    event RoundFinshed(uint8 round, uint amount, bool result, uint timestamp);
    event FundsAvailable(address to, uint8 round, uint amount, uint timestamp);

    ERC20Basic public token; // Token
    address public benificiary; // benificiary of ETH
    address public roundValidator; // Round validator is required to approve the new round creation

    uint8 public minPositivePercent; //Minimal allowed percent of positive votes
    uint public minTokensRequired;
    uint8 public currentRound; // Current round
    RoundState public state;

    mapping (uint8 => Round) roundStorage; // Rounds are stored here
    mapping (uint8 => bool) approvedRound; //Round approvals

    modifier onlyBenificiary() {
      require(msg.sender == benificiary);
      _;
    }

    modifier onlyFailed() {
      Round storage round = roundStorage[currentRound];
      require(round.finishedAt != 0);
      require(!round.result);
      require(state == RoundState.Waiting);
      _;
    }

    modifier onlyRoundValidator() {
      require(msg.sender == roundValidator);
      _;
    }

    modifier waitingState() {
      assert(state == RoundState.Waiting);
      _;
    }

    modifier approvalState() {
      assert(state == RoundState.Approval);
      _;
    }

    modifier activeState() {
      assert(state == RoundState.Active);
      _;
    }

    modifier canVote(uint8 _round) {
      Round storage round = roundStorage[_round];
      uint _tokenBalance = token.balanceOf(msg.sender);
      require(_tokenBalance >= round.minTokens);
      _;
    }

    // @constructor
    function Escrow(address _token, address _benificiary, address _validator) public {
      token = ERC20Basic(_token);
      benificiary = _benificiary;
      roundValidator = _validator;
    }

    // Set minimal positive percent for the rounds
    // @param uint8 percent
    function setMinPositivePercent(uint8 _percent) public onlyOwner {
      minPositivePercent = _percent;
    }

    // Set round validator. Only owner
    // @param address _validator the new validator
    function setRoundValidator(address _validator) public onlyOwner {
      roundValidator = _validator;
    }

    // Validate round (is required round valid)
    // @param uint8 _number the Round number to approve or decline
    // @param bool _result true == approved, false == declined
    function validateRound(uint8 _number, bool _result) public onlyRoundValidator approvalState {
        require(_number == currentRound); //Disable approval in advance
        approvedRound[_number] = _result;
        Round storage round = roundStorage[_number];
        if (_result == true) {
          Approved(msg.sender, _number, round.ETHAmount, now);
          startRound();
        } else {
          Rejected(msg.sender, _number, round.ETHAmount, now);
        }
    }

    // Initiate new voting round. Can be called by the benificiary
    // @param uint _amount - amount of ETH to initiate tranche for
    // @param string _reason - the reason of spendings
    // @param strig _message -  attached message
    // @param uint _minTokens - minimal amount of tokens required to vote
    // @param uint8 _positivePercent - percent of positive votes to succeed
    function initiateRound(
      uint _amount, string _reason, string _message,
      uint _minTokens, uint8 _positivePercent,
      uint _startAfter, uint _endAfter
      ) public onlyBenificiary waitingState {
        require(_positivePercent >= _positivePercent);
        require(_startAfter <= _endAfter);
        require(this.balance >= _amount);
        require(_minTokens >= minTokensRequired);
        currentRound++;
        Round storage round = roundStorage[currentRound];
        round.number = currentRound;
        round.reason = _reason;
        round.message = _message;
        round.ETHAmount = _amount;
        round.minTokens = _minTokens;
        round.positivePercent = _positivePercent;
        round.startAfter = _startAfter;
        round.endAfter = _endAfter;
        InitRound(currentRound, _amount, _reason, _message);
        state = RoundState.Approval;
    }


    // Start the new round if its approved
    function startRound() internal {
      require(approvedRound[currentRound] == true);
      Round storage round = roundStorage[currentRound];
      require(round.startAfter <= now);
      require(round.endAfter >= now);
      round.startedAt = now;
      state = RoundState.Active;
      RoundStarted(currentRound, round.ETHAmount, now);
    }

    // Vote in current round can be only called in the active state by the token
    // holder with more then minimal required tokens in the current round
    // @param bool _vote - true if accept payment false to decline
    function vote(bool _vote) public canVote(currentRound) activeState {
      Round storage round = roundStorage[currentRound];
      require(round.endAfter >= now);
      require(round.votes[msg.sender] == 0);
      round.votes[msg.sender] = now;
      if (_vote) {
        round.positive++;
      } else {
        round.negative++;
      }
      Vote(msg.sender, currentRound, token.balanceOf(msg.sender), _vote);
    }

    // Calculate votes and stop this round
    function finalizeRound() public activeState {
      Round storage round = roundStorage[currentRound];
      require(round.endAfter >= now);
      uint totalVotes = round.positive.add(round.negative);
      uint8 positivePercent = uint8(round.positive.div(totalVotes).mul(100));
      round.finishedAt = now;
      if (positivePercent >= round.positivePercent) {
          round.result = true;
          asyncSend(benificiary, round.ETHAmount);
          FundsAvailable(benificiary, round.number, round.ETHAmount, now);
      } else {
        round.result = false;
      }
      RoundFinshed(currentRound, round.ETHAmount, round.result, now);
      state = RoundState.Waiting;
    }


    // Calculate the reefund voters will get
    function calculateRefund(uint _tokens, uint _tokenSupply, uint _ethAmount) internal returns(uint) {
      uint ethPerToken = _ethAmount.div(_tokenSupply);
      return _tokens.mul(ethPerToken);
    }

    function getRefund() public onlyFailed {
        Round storage round = roundStorage[currentRound];
        require(round.refunds[msg.sender] == 0);
        uint refundAmount = calculateRefund(
          token.balanceOf(msg.sender),
          token.totalSupply(),
          round.ETHAmount
        );
        round.refunds[msg.sender] = refundAmount;
        msg.sender.transfer(refundAmount);
    }

}
