pragma solidity 0.4.24;

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

contract MTSH is owned {
    using SafeMath for uint256;

    string public name = "Mitoshi";
    string public symbol = "MTSH";
    uint8 public decimals = 18;
    uint256 DEC = 10 ** uint256(decimals);

    uint256 public totalSupply = 1000000000 * DEC;
    uint256 public tokensForSale = 680000000 * DEC;
    uint256 minPurchase = 1 ether;
    uint256 rate = 2000; // 1 ETH = 2000 Mitoshi tokens

    enum State {Active, Refunding, Closed}
    State public state;

    struct Round {
        uint256 _hardCap;
        uint256 _bonus;
    }
    mapping(uint => Round) public roundInfo;
    Round public currentRound;

    constructor() public {
        roundInfo[0] = Round(
            50000 * 1 ether,
            20
        );
        roundInfo[1] = Round(
            50000 * 1 ether,
            10
        );
        roundInfo[2] = Round(
            150000 * 1 ether,
            0
        );

        balanceOf[msg.sender] = totalSupply;

        state = State.Active;

        currentRound = roundInfo[0];
    }

    mapping(address => uint256) deposited;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed from, uint256 value);
    event RefundsEnabled();
    event Refunded(address indexed beneficiary, uint256 weiAmount);

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
        require(address(this).balance <= currentRound._hardCap);
        uint amount = rate.mul(msg.value);
        uint bonus = currentRound._bonus;
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

    function refund(address investor) public {
        require(state == State.Refunding);
        require(deposited[investor] > 0);
        uint256 depositedValue = deposited[investor];
        investor.transfer(depositedValue);
        deposited[investor] = 0;
        emit Refunded(investor, depositedValue);
    }

    function withdraw(uint amount) onlyOwner public returns (bool) {
        require(amount <= address(this).balance);
        owner.transfer(amount);
        return true;
    }

    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(_value);
        emit Burn(msg.sender, _value);
        return true;
    }
}