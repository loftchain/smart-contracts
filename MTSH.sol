pragma solidity 0.4.25;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}

contract owned {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

interface tokenRecipient {
    function receiveApproval(
        address _from,
        uint256 _value,
        address _token,
        bytes _extraData
    ) external;
}

contract MTSH is owned, usingOraclize {
    using SafeMath for uint256;

    string public name = "Mitoshi";
    string public symbol = "MTSH";
    uint8 public decimals = 18;
    uint256 DEC = 10 ** uint256(decimals);

    uint256 public totalSupply = 1000000000 * DEC;
    uint256 public tokensForSale = 680000000 * DEC;
    uint256 minPurchase = 1 ether;
    uint256 public curs = 250;
    uint256 public cost = 2 * DEC / 10;
    uint256 public rate =  1 ether * curs /cost;
    uint256 public oraclizeBalance;

    enum State {Active, Refunding, Closed}
    State public state;

    function __callback(bytes32 myid, string result) {
        if (msg.sender != oraclize_cbAddress()) revert();
        curs = parseInt(result);
        rate =  1 ether * curs /cost;
        LogPriceUpdated(result);
        updatePrice();
    }

    constructor() public {
        balanceOf[msg.sender] = totalSupply;
        state = State.Active;
    }

    mapping(address => uint256) deposited;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed from, uint256 value);
    event RefundsEnabled();
    event Closed();
    event Refunded(address indexed beneficiary, uint256 weiAmount);
    event LogPriceUpdated(string price);
    event LogNewOraclizeQuery(string description);

    modifier transferredIsOn {
        require(state == State.Closed);
        _;
    }

    function transfer(address _to, uint256 _value) transferredIsOn public {
        _transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) transferredIsOn public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);
        allowance[_from][msg.sender] = allowance[_from][msg.sender].sub(_value);
        _transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        require((_value == 0) || (allowance[msg.sender][_spender] == 0));

        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
    public
    returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    function transferOwner(address _to, uint256 _value) onlyOwner public {
        _transfer(msg.sender, _to, _value);
    }

    function _transfer(address _from, address _to, uint _value) internal {
        require(_to != 0x0);
        require(balanceOf[_from] >= _value);
        require(balanceOf[_to].add(_value) >= balanceOf[_to]);
        balanceOf[_from] = balanceOf[_from].sub(_value);
        balanceOf[_to] = balanceOf[_to].add(_value);
        emit Transfer(_from, _to, _value);
    }

    function buyTokens(address beneficiary) payable public {
        require(state == State.Active);
        require(msg.value >= minPurchase);
        uint amount = rate.mul(msg.value);
        uint bonus = getBonusPercent();
        amount = amount.add(amount.mul(bonus).div(100));

        _transfer(owner, msg.sender, amount);

        tokensForSale = tokensForSale.sub(amount);
        deposited[beneficiary] = deposited[beneficiary].add(msg.value);
    }

    function() external payable {
        buyTokens(msg.sender);
    }

    function enableRefunds() onlyOwner public {
        require(state == State.Active);
        state = State.Refunding;
        emit RefundsEnabled();
    }

    function close() onlyOwner public {
        state = State.Closed;
        emit Closed();
    }

    function refund(address investor) public {
        require(state == State.Refunding);
        require(deposited[investor] > 0);
        uint256 depositedValue = deposited[investor];
        investor.transfer(depositedValue);
        deposited[investor] = 0;
        emit Refunded(investor, depositedValue);
    }

    function withdrawBalance() onlyOwner external {
        require(address(this).balance > 0);
        owner.transfer(address(this).balance);
    }

    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(_value);
        emit Burn(msg.sender, _value);
        return true;
    }

    function updateCurs(uint256 _value) onlyOwner public {
        curs = _value;
        rate =  1 ether * curs /cost;
    }

    //1 Sept 1200 UTC to 24 Sept 2018 1200 UTC– Launch of Website / QA / Private Sale 0.1$
    //24 Sept 1200 UTC to 29 Oct 1200 2018 UTC – Pre Sale / Token Price is US$0.14 with 30% Bonus
    //29 Oct 1200 UTC to 26 Nov 2018 1200 UTC – Pre Sale / Token Price is US$0.16 with 20% Bonus
    //26 Nov 1200 UTC to 31 Dec 1200 2018 UTC – Pre Sale / Token Price is US$0.18 with 10% Bonus
    //31 Dec 2018 1200 UTC to 28 Jan 2019 1200 UTC – ICO Proper / Token Price is US$.20
    function getBonusPercent() internal view returns(uint _bonus) {
        //1535803200 = 01/09/2018 @ 12:00pm (UTC)
        //1537790400 = 24/09/2018 @ 12:00pm (UTC)
        if (block.timestamp >= 1535803200 && block.timestamp < 1537790400) {
            return 50;
        //1540814400 = 29/10/2018 @ 12:00pm (UTC)
        } else if (block.timestamp >= 1537790400 && block.timestamp < 1540814400) {
            return 30;
        //1543233600 = 11/26/2018 @ 12:00pm (UTC)
        } else if (block.timestamp >= 1540814400 && block.timestamp < 1543233600) {
            return 20;
        //1546257600 = 31/12/2018 @ 12:00pm (UTC)
        } else if (block.timestamp >= 1543233600 && block.timestamp < 1546257600) {
            return 10;
        } else return 0;
    }

    function updatePrice() payable {
        if (oraclize_getPrice("URL") > this.balance) {
            LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            LogNewOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            //43200 = 12 hour
            oraclize_query(43200, "URL", "json(https://api.gdax.com/products/ETH-USD/ticker).price");
        }
    }

    function setGasPrice(uint _newPrice) public onlyOwner {
        oraclize_setCustomGasPrice(_newPrice * 1 wei);
    }

    function addBalanceForOraclize() payable external {
        oraclizeBalance = oraclizeBalance.add(msg.value);
    }
}