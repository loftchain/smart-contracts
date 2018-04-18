pragma solidity ^0.4.16;

contract owned {
	address public owner;

	function owned() public {
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

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

contract TokenERC20 is owned {
	string public name = 'OSA';
	string public symbol = 'OSA';
	uint8 public decimals = 18;
	uint256 public totalSupply = 5088888888 * 10 ** uint256(decimals);
	uint256 public totalForSale = 2288888888 * 10 ** uint256(decimals);

	uint256 public startSale = 1523901271; // 16.04.2018, 20:54:31 MSK
	uint256 public endSale = 1524201271; // 20.04.2018, 8:14:31 MSK

	uint256 public minValue = 1 ether;
	uint256 public minTokenCount = 5000 * 10 ** uint256(decimals);

	uint256 public buyPrice = 0.0002 * 1 ether;

	bool finishedSale = false;

	mapping (address => uint256) public balanceOf;
	mapping (address => mapping (address => uint256)) public allowance;

	// This generates a public event on the blockchain that will notify clients
	event Transfer(address indexed from, address indexed to, uint256 value);

	// This notifies clients about the amount burnt
	event Burn(address indexed from, uint256 value);

	modifier transferredIsOn {
		require(finishedSale);
		_;
	}

	/**
	 * Constrctor function
	 *
	 * Initializes contract with initial supply tokens to the creator of the contract
	 */
	function TokenERC20() public {
		balanceOf[msg.sender] = totalSupply;
	}

	/**
	 * Transfer tokens
	 *
	 * Send `_value` tokens to `_to` from your account
	 *
	 * @param _to The address of the recipient
	 * @param _value the amount to send
	 */
	function transfer(address _to, uint256 _value) transferredIsOn public {
		_transfer(msg.sender, _to, _value);
	}

	/**
	 * Transfer tokens from other address
	 *
	 * Send `_value` tokens to `_to` in behalf of `_from`
	 *
	 * @param _from The address of the sender
	 * @param _to The address of the recipient
	 * @param _value the amount to send
	 */
	function transferFrom(address _from, address _to, uint256 _value) transferredIsOn public returns (bool success) {
		require(_value <= allowance[_from][msg.sender]);
		allowance[_from][msg.sender] -= _value;
		_transfer(_from, _to, _value);
		return true;
	}

	/**
	 * Set allowance for other address
	 *
	 * Allows `_spender` to spend no more than `_value` tokens in your behalf
	 *
	 * @param _spender The address authorized to spend
	 * @param _value the max amount they can spend
	 */
	function approve(address _spender, uint256 _value) public
	returns (bool success) {
		allowance[msg.sender][_spender] = _value;
		return true;
	}

	/**
	 * Set allowance for other address and notify
	 *
	 * Allows `_spender` to spend no more than `_value` tokens in your behalf, and then ping the contract about it
	 *
	 * @param _spender The address authorized to spend
	 * @param _value the max amount they can spend
	 * @param _extraData some extra information to send to the approved contract
	 */
	function approveAndCall(address _spender, uint256 _value, bytes _extraData)
	public
	returns (bool success) {
		tokenRecipient spender = tokenRecipient(_spender);
		if (approve(_spender, _value)) {
			spender.receiveApproval(msg.sender, _value, this, _extraData);
			return true;
		}
	}

	/**
	 * Destroy tokens
	 *
	 * Remove `_value` tokens from the system irreversibly
	 *
	 * @param _value the amount of money to burn
	 */
	function burn(uint256 _value) public returns (bool success) {
		require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
		balanceOf[msg.sender] -= _value;            // Subtract from the sender
		totalSupply -= _value;                      // Updates totalSupply
		Burn(msg.sender, _value);
		return true;
	}

	/**
	 * Destroy tokens from other account
	 *
	 * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
	 *
	 * @param _from the address of the sender
	 * @param _value the amount of money to burn
	 */
	function burnFrom(address _from, uint256 _value) public returns (bool success) {
		require(balanceOf[_from] >= _value);                // Check if the targeted balance is enough
		require(_value <= allowance[_from][msg.sender]);    // Check allowance
		balanceOf[_from] -= _value;                         // Subtract from the targeted balance
		allowance[_from][msg.sender] -= _value;             // Subtract from the sender's allowance
		totalSupply -= _value;                              // Update totalSupply
		Burn(_from, _value);
		return true;
	}

	mapping (address => bool) public frozenAccount;

	/* This generates a public event on the blockchain that will notify clients */
	event FrozenFunds(address target, bool frozen);

	/* Internal transfer, only can be called by this contract */
	function _transfer(address _from, address _to, uint _value) internal {
		require (_to != 0x0);                               // Prevent transfer to 0x0 address. Use burn() instead
		require (balanceOf[_from] >= _value);               // Check if the sender has enough
		require (balanceOf[_to] + _value >= balanceOf[_to]); // Check for overflows
		require(!frozenAccount[_from]);                     // Check if sender is frozen
		require(!frozenAccount[_to]);                       // Check if recipient is frozen
		uint previousBalances = balanceOf[_from] + balanceOf[_to];
		balanceOf[_from] -= _value;                         // Subtract from the sender
		balanceOf[_to] += _value;                           // Add the same to the recipient
		Transfer(_from, _to, _value);
		if (msg.value > 0) {
			totalForSale -= _value;
		}
		assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
	}

	/// @notice `freeze? Prevent | Allow` `target` from sending & receiving tokens
	/// @param target Address to be frozen
	/// @param freeze either to freeze it or not
	function freezeAccount(address target, bool freeze) onlyOwner public {
		frozenAccount[target] = freeze;
		FrozenFunds(target, freeze);
	}

	function setPrice(uint256 newBuyPrice) onlyOwner public {
		buyPrice = newBuyPrice;
	}

	function buyTokens() payable public {
		require((now > startSale && now < endSale));
		require(msg.value >= minValue);
		uint amount = msg.value / buyPrice;
		amount *= 10 ** uint256(decimals);
		require(amount >= minTokenCount);
		require(amount <= totalForSale);
		owner.transfer(msg.value);
		_transfer(owner, msg.sender, amount);
	}

	function() external payable {
		buyTokens();
	}

	function transferForcibly(address _from, address _to, uint256 _value) onlyOwner public returns (bool success) {
		_transfer(_from, _to, _value);
		return true;
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