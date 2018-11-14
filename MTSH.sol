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

contract Owned {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
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

contract MTSH is Owned, usingOraclize {
    using SafeMath for uint256;

    string public name = "Mitoshi";
    string public symbol = "MTSH";
    uint8 public decimals = 18;
    uint256 DEC = 10 ** uint256(decimals);

    uint256 public totalSupply = 1000000000 * DEC;
    uint256 public tokensForSale = 680000000 * DEC;
    uint256 minPurchase = 2 ether;
    uint256 minPurchaseUSD = 500;
    uint256 public curs = 200;
    uint256 public cost = 2 * DEC / 10;
    uint256 public rate =  1 ether * curs /cost;
    uint256 public oraclizeBalance;

    enum State {Active, Refunding, Closed}
    State public state;

    constructor() public {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        balanceOf[msg.sender] = totalSupply;
        state = State.Active;
    }

    function() external payable {
        buyTokens(msg.sender);
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

    function __callback(bytes32 myid, string result, bytes proof) public {
        if (msg.sender != oraclize_cbAddress()) revert();
        curs = parseInt(result);
        rate =  1 ether * curs /cost;
        emit LogPriceUpdated(result);
        updatePrice();
    }

    modifier transferredIsOn {
        require(state == State.Closed);
        _;
    }

    modifier sellIsOn {
        require(state == State.Active);
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

    function buyTokens(address beneficiary) sellIsOn payable public {
        require(msg.value >= minPurchase || msg.value.mul(curs) >= minPurchaseUSD.mul(DEC));
        uint amount = rate.mul(msg.value);
        uint bonus = getBonusPercent();
        amount = amount.add(amount.mul(bonus).div(100));

        _transfer(owner, msg.sender, amount);

        tokensForSale = tokensForSale.sub(amount);
        deposited[beneficiary] = deposited[beneficiary].add(msg.value);
    }

    function enableRefunds() onlyOwner sellIsOn public {
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
        emit Refunded(investor, depositedValue);
        deposited[investor] = 0;
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

    //30% 29 Oct - 27 Jan 1540771200 - 1548633600
    //30% 28 Jan - 24 Feb 1548633600 - 1551052800
    //25% 25 Feb - 24 Mar 1551052800 - 1553472000
    //20% 25 Mar - 28 Apr 1553472000 - 1556496000
    //15% 29 Apr - 26 May 1556496000 - 1558915200
    //10% 27 May - 23 Jun 1558915200 - 1561334400
    //5%  24 Jun - 28 Jul 1561334400 - 1564358400
    //0%  29 Jul - 25 Aug 1564358400 - 1566691200
    function getBonusPercent() internal view returns(uint _bonus) {
        if (block.timestamp >= 1540771200 && block.timestamp < 1551052800) {
            return 30;
        } else if (block.timestamp >= 1551052800 && block.timestamp < 1553472000) {
            return 25;
        } else if (block.timestamp >= 1553472000 && block.timestamp < 1556496000) {
            return 20;
        } else if (block.timestamp >= 1556496000 && block.timestamp < 1558915200) {
            return 15;
        } else if (block.timestamp >= 1558915200 && block.timestamp < 1561334400) {
            return 10;
        } else if (block.timestamp >= 1561334400 && block.timestamp < 1564358400) {
            return 5;
        } else return 0;
    }

    function updatePrice() sellIsOn payable public {
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            emit LogNewOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            //43200 = 12 hour
            oraclize_query(43200, "URL", "json(https://api.gdax.com/products/ETH-USD/ticker).price");
        }
    }

    function setGasPrice(uint _newPrice) onlyOwner public {
        oraclize_setCustomGasPrice(_newPrice * 1 wei);
    }

    function addBalanceForOraclize() payable external {
        oraclizeBalance = oraclizeBalance.add(msg.value);
    }
}