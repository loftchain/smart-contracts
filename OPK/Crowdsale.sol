pragma solidity ^0.4.24;

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
    address public ICOAddress;

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
     * @dev Throws if called by any account other than the ico.
     */
    modifier onlyICO() {
        require(msg.sender == ICOAddress);
        _;
    }


    modifier onlyOwnerOrICO() {
        require(msg.sender == ICOAddress || msg.sender == owner);
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

    function setICOAddress(address _icoAddress) public onlyOwner {
        require(_icoAddress != address(0));
        ICOAddress = _icoAddress;
    }
}

contract ERC20 {
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function totalSupply() public view returns (uint256);
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeERC20 {
    function safeTransfer(ERC20 token, address to, uint256 value) internal {
        require(token.transfer(to, value));
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
contract Crowdsale is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    // The token being sold
    ERC20 public token;
    RefundEscrow private escrow;
    address public wallet;

    uint256 public openingTime;
    uint256 public closingTime;

    uint256 public cap;

    bool public isFinalized = false;

    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    // So, if you are using a rate of 1 with a DetailedERC20 token with 3 decimals called TOK
    // 1 wei will give you 1 unit, or 0.001 TOK.
    uint256 public rate;

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


    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event Finalized();
    /**
     * @dev Reverts if not in crowdsale time range.
     */
    modifier onlyWhileOpen {
        // solium-disable-next-line security/no-block-members
        require(block.timestamp >= openingTime && block.timestamp <= closingTime);
        _;
    }

    /**
     * @param _rate Number of token units a buyer gets per wei
     * @param _wallet Address where collected funds will be forwarded to
     * @param _token Address of the token being sold
     * @param _openingTime Crowdsale opening time
     * @param _closingTime Crowdsale closing time
     */
    //TODO
//Soft Cap: $6 million
//Hard Cap: $30 million
//Min Purchase: 50 OPK ЭТО С УЧЕТОМ БОСУНА ?
//Max Purchase: 100 000 OPK  ЭТО С УЧЕТОМ БОСУНА ?
    constructor(uint256 _rate, address _wallet, ERC20 _token, uint256 _cap,
                uint256 _openingTime, uint256 _closingTime) public {
        require(_rate > 0);
        require(_wallet != address(0));
        require(_token != address(0));
        require(_openingTime >= block.timestamp);
        require(_closingTime >= _openingTime);
        require(_cap > 0);


        rate = _rate;
        wallet = _wallet;
        token = _token;

        escrow = new RefundEscrow(wallet);

        cap = _cap;
        openingTime = _openingTime;
        closingTime = _closingTime;


        currentStage = 1;
        addStage(openingTime + 1  days, 2000, 2250, 2500);
        addStage(openingTime + 8  days, 1500, 1750, 2000);
        addStage(openingTime + 15  days, 500, 750, 1000);
        addStage(openingTime + 22  days, 100, 100, 100);
        addStage(openingTime + 29  days, 0, 0, 0);
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


    function addStage(uint _stopDay, uint _bonus) onlyOwner public {
        require(_stopDay > stages[stageCount].stopDay);
        stageCount++;
        stages[stageCount].stopDay = _stopDay;
        stages[stageCount].bonus = _bonus;
    }

    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * @param _beneficiary Address performing the token purchase
     */
    function buyTokens(address _beneficiary) public payable {

        uint256 weiAmount = msg.value;
        _preValidatePurchase(_beneficiary, weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(weiAmount);

        // update state
        weiRaised = weiRaised.add(weiAmount);

        _processPurchase(_beneficiary, tokens);
        emit TokenPurchase(msg.sender, _beneficiary, weiAmount, tokens);

        //_updatePurchasingState(_beneficiary, weiAmount);

        _forwardFunds();
        //_postValidatePurchase(_beneficiary, weiAmount);
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
        require(_weiAmount != 0);
        require(weiRaised.add(_weiAmount) <= cap);
    }

    /**
     * @dev Validation of an executed purchase. Observe state and use revert statements to undo rollback when valid conditions are not met.
     * @param _beneficiary Address performing the token purchase
     * @param _weiAmount Value in wei involved in the purchase
     */
    // function _postValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
    //     // optional override
    // }

    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the token purchase
     * @param _tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        token.safeTransfer(_beneficiary, _tokenAmount);
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
     * @dev Override for extensions that require an internal state to check for validity (current user contributions, etc.)
     * @param _beneficiary Address receiving the tokens
     * @param _weiAmount Value in wei involved in the purchase
     */
    // function _updatePurchasingState(address _beneficiary, uint256 _weiAmount) internal {
    //     // optional override
    // }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 _weiAmount) internal view returns (uint256) {

        if (stages[currentStage].stopDay <= now) {
            _updateCurrentStage();
        }

        return _weiAmount.mul(rate);

    }


    function _updateCurrentStage() internal {
        for (uint i = currentStage; i <= stageCount; i++) {
            if (stages[i].stopDay > now) {
                currentStage = i;
                break;
            }
        }
    }

    /**
     * @dev Overrides Crowdsale fund forwarding, sending funds to escrow.
     */
    function _forwardFunds() internal {
        wallet.transfer(msg.value);
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
        //TODO SEND TOKENS TO RESERFFOUND
    }


    //1% - 100, 10% - 1000 50% - 5000
    function valueFromPercent(uint _value, uint _percent) internal pure returns (uint amount)    {
        uint _amount = _value.mul(_percent).div(10000);
        return (_amount);
    }
}
