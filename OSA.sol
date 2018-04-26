pragma solidity 0.4.23;

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

interface tokenRecipient {function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) external;}

contract TokenERC20 is owned {
	using SafeMath for uint256;

	string public name = "OSA";
	string public symbol = "OSA";
	uint8 public decimals = 18;
	uint256 public totalSupply = 5088888888 * (10 ** uint256(decimals));
	uint256 public totalForSale = 2288888888 * (10 ** uint256(decimals));

	uint256 public startSale = 1523901271;
	uint256 public endSale = 1535201271;

	uint256 public minValue = 1 ether;
	uint256 public minTokenCount = 5000 * (10 ** uint256(decimals));

	uint256 public buyPrice = 0.0002 * 1 ether;

	bool finishedSale = false;

	mapping(address => uint256) public balanceOf;
	mapping(address => mapping(address => uint256)) public allowance;

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
	event Burn(address indexed from, uint256 value);

	constructor() public {
		balanceOf[msg.sender] = totalSupply;
	}

	modifier transferredIsOn {
		require(finishedSale);
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

	function burn(uint256 _value) public returns (bool success) {
		require(balanceOf[msg.sender] >= _value);
		balanceOf[msg.sender] = balanceOf[msg.sender].sub(_value);
		totalSupply = totalSupply.sub(_value);
		emit Burn(msg.sender, _value);
		return true;
	}

	function burnFrom(address _from, uint256 _value) public returns (bool success) {
		require(balanceOf[_from] >= _value);
		require(_value <= allowance[_from][msg.sender]);
		balanceOf[_from] = balanceOf[_from].sub(_value);
		allowance[_from][msg.sender] = allowance[_from][msg.sender].sub(_value);
		totalSupply = totalSupply.sub(_value);
		emit Burn(_from, _value);
		return true;
	}

	mapping(address => bool) public frozenAccount;

	event FrozenFunds(address target, bool frozen);

	function _transfer(address _from, address _to, uint _value) internal {
		require(_to != 0x0);
		require(balanceOf[_from] >= _value);
		require(balanceOf[_to].add(_value) >= balanceOf[_to]);
		require(!frozenAccount[_from]);
		require(!frozenAccount[_to]);
		uint previousBalances = balanceOf[_from].add(balanceOf[_to]);
		balanceOf[_from] = balanceOf[_from].sub(_value);
		balanceOf[_to] = balanceOf[_to].add(_value);
		emit Transfer(_from, _to, _value);
		if (msg.value > 0) {
			totalForSale = totalForSale.sub(_value);
		}
		assert(balanceOf[_from].add(balanceOf[_to]) == previousBalances);
	}

	function freezeAccount(address target, bool freeze) onlyOwner public {
		frozenAccount[target] = freeze;
		emit FrozenFunds(target, freeze);
	}

	function setPrice(uint256 newBuyPrice) onlyOwner public {
		buyPrice = newBuyPrice;
	}

	function buyTokens() payable public {
		require((now > startSale && now < endSale));
		require(msg.value >= minValue);
		uint amount = msg.value.div(buyPrice);
		amount = amount.mul(10 ** uint256(decimals));
		require(amount >= minTokenCount);
		require(amount <= totalForSale);
		owner.transfer(msg.value);
		_transfer(owner, msg.sender, amount);
	}

	function() external payable {
		buyTokens();
	}

	function finishSale() onlyOwner public {
		finishedSale = true;
		burn(totalForSale);
		totalForSale = 0;
	}

	function setStartSale(uint256 newStartSale) onlyOwner public {
		startSale = newStartSale;
	}

	function setEndSale(uint256 newEndSale) onlyOwner public {
		endSale = newEndSale;
	}
}