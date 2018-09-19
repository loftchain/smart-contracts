pragma solidity 0.4.24;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}

contract Ownable {
    address public owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );


    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }


    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param _newOwner The address to transfer ownership to.
    */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0));
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

}

contract ERC20 {
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function totalSupply() public view returns (uint256);
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function ownerTransfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function unpause() public returns (bool);
}

library SafeERC20 {
    function safeTransfer(ERC20 token, address to, uint256 value) internal {
        require(token.transfer(to, value));
    }

    function safeOwnerTransfer(ERC20 token, address to, uint256 value) internal {
        require(token.ownerTransfer(to, value));
    }

    function safeTransferFrom(ERC20 token, address from, address to, uint256 value) internal {
        require(token.transferFrom(from, to, value));
    }

    function safeApprove(ERC20 token, address spender, uint256 value) internal {
        require(token.approve(spender, value));
    }
}



/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conform
 * the base architecture for crowdsales. They are *not* intended to be modified / overriden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropiate to concatenate
 * behavior.
 */
contract Crowdsale is Ownable, usingOraclize{
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    // The token being sold
    ERC20 public token;
    address public wallet;
    address public reserveFund;

    uint256 public openingTime;
    uint256 public closingTime;

    uint256 public cap;
    uint256 public tokensSold;
    uint256 public tokenPriceInWei;

    bool public isFinalized = false;

    // Amount of wei raised
    uint256 public weiRaised;


    struct Stage {
        uint stopDay;
        uint bonus1;
        uint bonus2;
        uint bonus3;
    }

    mapping (uint => Stage) public stages;
    uint public stageCount;
    uint public currentStage;

    mapping (bytes32 => bool) public pendingQueries;
    mapping (address => bool) public KYC;

    uint public oraclizeBalance;

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 tokens, uint256 bonus);
    event Finalized();
    event NewOraclizeQuery(string description);
    event NewKrakenPriceTicker(string price);

    /**
     * @dev Reverts if not in crowdsale time range.
     */
    modifier onlyWhileOpen {
        // solium-disable-next-line security/no-block-members
        require(block.timestamp >= openingTime && block.timestamp <= closingTime);
        _;
    }


    constructor(address _wallet, ERC20 _token, uint256 _cap, uint256 _openingTime, uint256 _closingTime,
        address _reserveFund, uint256 _tokenPriceInWei) public {

        require(_wallet != address(0));
        require(_token != address(0));
        require(_reserveFund != address(0));
        require(_openingTime >= block.timestamp);
        require(_closingTime >= _openingTime);
        require(_cap > 0);
        require(_tokenPriceInWei > 0);

        wallet = _wallet;
        token = _token;
        reserveFund = _reserveFund;

        cap = _cap;
        openingTime = _openingTime;
        closingTime = _closingTime;
        tokenPriceInWei = _tokenPriceInWei;

        currentStage = 1;
        //TODO change days
        //        addStage(openingTime + 1  days, 2000, 2250, 2500);
        //        addStage(openingTime + 8  days, 1500, 1750, 2000);
        //        addStage(openingTime + 15  days, 500, 750, 1000);
        //        addStage(openingTime + 22  days, 100, 100, 100);
        //        addStage(openingTime + 29  days, 0, 0, 0);

        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        updatePrice();
    }

    // -----------------------------------------
    // Crowdsale external interface
    // -----------------------------------------

    /**
     * @dev fallback function ***DO NOT OVERRIDE***
     */
    function () external payable {
        buyTokens(msg.sender);
    }


    function __callback(bytes32 myid, string result, bytes proof) public {
        if (msg.sender != oraclize_cbAddress()) revert();
        require (pendingQueries[myid] == true);
        proof;
        emit NewKrakenPriceTicker(result);
        uint USD = parseInt(result);
        tokenPriceInWei = 1 ether / USD;
        updatePrice();
        delete pendingQueries[myid];
    }


    function updatePrice() public payable {
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit NewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            emit NewOraclizeQuery("Oraclize query was sent, standing by for the answer..");

            bytes32 queryId = oraclize_query(14400, "URL", "json(https://api.kraken.com/0/public/Ticker?pair=ETHUSD).result.XETHZUSD.c.0");
            pendingQueries[queryId] = true;
        }
    }


    function addStage(uint _stopDay, uint _bonus1, uint _bonus2, uint _bonus3) onlyOwner public {
        require(_stopDay > stages[stageCount].stopDay);
        stageCount++;
        stages[stageCount].stopDay = _stopDay;
        stages[stageCount].bonus1 = _bonus1;
        stages[stageCount].bonus2 = _bonus2;
        stages[stageCount].bonus3 = _bonus3;
        if (closingTime < _stopDay) {
            closingTime = _stopDay;
        }
    }

    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * @param _beneficiary Address performing the token purchase
     */
    function buyTokens(address _beneficiary) public payable {

        uint256 weiAmount = msg.value;
        _preValidatePurchase(_beneficiary, weiAmount);

        uint tokens = 0;
        uint bonusTokens = 0;
        uint totalTokens = 0;

        (tokens, bonusTokens, totalTokens) = _getTokenAmount(weiAmount);

        _validatePurchase(tokens);

        uint256 price = tokens.div(1 ether).mul(tokenPriceInWei);

        uint256 _diff =  weiAmount.sub(price);

        if (_diff > 0) {
            weiAmount = weiAmount.sub(_diff);
            msg.sender.transfer(_diff);
        }

        _processPurchase(_beneficiary, totalTokens);
        emit TokenPurchase(msg.sender, _beneficiary, weiAmount, tokens, bonusTokens);

        _updateState(weiAmount, totalTokens);

        _forwardFunds(weiAmount);
    }


    function manualSale(address _beneficiary, uint256 _tokens) onlyOwner external {
        require(_beneficiary != address(0));
        _validatePurchase(_tokens);
        uint256 weiAmount = _tokens.mul(tokenPriceInWei);

        _processPurchase(_beneficiary, _tokens);
        emit TokenPurchase(msg.sender, _beneficiary, weiAmount, _tokens, 0);
        _updateState(weiAmount, _tokens);
    }

    // -----------------------------------------
    // Internal interface (extensible)
    // -----------------------------------------

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
     * @param _beneficiary Address performing the token purchase
     * @param _weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) onlyWhileOpen internal view{
        require(_beneficiary != address(0));
        require(KYC[_beneficiary]);
        require(_weiAmount != 0);
        require(tokensSold < cap);
    }


    function _validatePurchase(uint256 _tokens) internal view {
        require(_tokens >= 50 ether && _tokens <= 100000 ether);
        require(tokensSold.add(_tokens) <= cap);
    }


    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the token purchase
     * @param _tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        token.safeOwnerTransfer(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
     * @param _beneficiary Address receiving the tokens
     * @param _tokenAmount Number of tokens to be purchased
     */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        _deliverTokens(_beneficiary, _tokenAmount);
    }


    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */

    function _getTokenAmount(uint256 _weiAmount) internal returns (uint,uint,uint) {
        uint tokens = _weiAmount.div(tokenPriceInWei).mul(1 ether);

        if (stages[currentStage].stopDay <= now) {
            _updateCurrentStage();
        }

        uint bonus = 0;

        if (_weiAmount < 10 ether) {
            bonus = stages[currentStage].bonus1;
        }

        if (_weiAmount >= 10 ether && _weiAmount < 100 ether) {
            bonus = stages[currentStage].bonus2;
        }

        if (_weiAmount >= 100 ether) {
            bonus = stages[currentStage].bonus3;
        }

        bonus = tokens.mul(bonus).div(10000);

        uint total = tokens.add(bonus);

        if (tokensSold.add(total) > cap) {
            total = cap.sub(tokensSold);
            bonus = total.mul(bonus).div(10000 + bonus);
            tokens = total.sub(bonus);
        }

        return (tokens, bonus, total);
    }


    function _updateCurrentStage() internal {
        for (uint i = currentStage; i <= stageCount; i++) {
            if (stages[i].stopDay > now) {
                currentStage = i;
                break;
            }
        }
    }


    function _updateState(uint256 _weiAmount, uint256 _tokens) internal {
        weiRaised = weiRaised.add(_weiAmount);
        tokensSold = tokensSold.add(_tokens);
    }

    /**
     * @dev Overrides Crowdsale fund forwarding, sending funds to escrow.
     */
    function _forwardFunds(uint _weiAmount) internal {
        wallet.transfer(_weiAmount);
    }

    /**
     * @dev Checks whether the period in which the crowdsale is open has already elapsed.
     * @return Whether crowdsale period has elapsed
     */
    function hasClosed() public view returns (bool) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp > closingTime;
    }


    /**
    * @dev Checks whether the cap has been reached.
    * @return Whether the cap was reached
    */
    function capReached() public view returns (bool) {
        return weiRaised >= cap;
    }


    /**
     * @dev Must be called after crowdsale ends, to do some extra finalization
     * work. Calls the contract's finalization function.
     */
    function finalize() onlyOwner public {
        require(!isFinalized);
        require(hasClosed() || capReached());

        finalization();
        emit Finalized();

        isFinalized = true;
    }

    /**
     * @dev Can be overridden to add finalization logic. The overriding function
     * should call super.finalization() to ensure the chain of finalization is
     * executed entirely.
     */
    function finalization() internal {
        if (token.balanceOf(this) > 0) {
            token.safeOwnerTransfer(reserveFund, token.balanceOf(this));
        }
        require(token.unpause());
    }


    //1% - 100, 10% - 1000 50% - 5000
    function valueFromPercent(uint _value, uint _percent) internal pure returns (uint amount)    {
        uint _amount = _value.mul(_percent).div(10000);
        return (_amount);
    }

    function addKYC(address _user) onlyOwner public {
        KYC[_user] = true;
    }

    function delKYC(address _user) onlyOwner public {
        KYC[_user] = false;
    }


    function addBalanceForOraclize() payable external {
        oraclizeBalance = oraclizeBalance.add(msg.value);
    }


    function withdrawBalance() onlyOwner external {
        require(address(this).balance > 0);
        owner.transfer(address(this).balance);
    }


    function setGasPrice(uint _newPrice) public onlyOwner {
        oraclize_setCustomGasPrice(_newPrice * 1 wei);
    }

}
