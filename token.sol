pragma solidity ^0.4.16;

// If supply is too large, buy back a set amount of burnmint to be burnt.
// We need to burn X burnmint, so the contract will offer locked ether to buy back burnmint.
// The buy back price is set through an auction.
// People bid for lowest amount of ether to receive for a fixed amount of burnmint.
// They stake X burnmint in the contract and send the expected ether to receive.
// Ether is sent to bidder at the end of the auction in exchange for the burnmint.
// Burnmint is burned to reach supply target.
//
// If supply is too low, mint a fixed amount of new burnmint.
// We need to mint X burnmint, so the contract will offer new burnmint to the market.
// The offer price is set through an auction.
// People bid the highest amount of Ether for the offered burnmint.
// They stake their ether in the contract.
// At the end of the auction, burnmint is sent to the highest bidder and the ether is deposited into the burnmint contract.
// 

interface tokenRecipient { 
    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; 
}

contract Burnmint {
    
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    // variables related to the voting mechanism
    uint256 public lockedSupply;
    uint256 public targetSupply;
    
    // variables related to the auctions
    bool public burnAuction;
    bool public auctionEnded;
    uint256 public auctionThreshold;
    uint256 public auctionAmount;
    address public currentBidder;
    uint256 public currentBid;
    
    // This creates an array with all balances
    mapping (address => uint256) public balanceOf;
    mapping (address => uint256) public supplyTargetOf;
    mapping (address => uint256) public lockedBalanceOf;
    mapping (address => uint256) public pendingReturns;
    mapping (address => uint256) public pendingBurnmint;
    mapping (address => mapping (address => uint256)) public allowance;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);
    
    // This notifies clients about the amount minted
    event Mint(address indexed to, uint256 value);
    
    // This notifies clients about a vote for supply
    event Vote(address indexed from, uint256 value, uint256 target);
    
    // This removal of vote for supply
    event Unvote(address indexed from, uint256 value);
    
    
    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    function Burnmint(
        uint256 initialSupply,
        uint256 tokenAuctionThreshold,
        string tokenName,
        string tokenSymbol
    ) public {
        totalSupply = initialSupply * 10 ** uint256(decimals);  // Update total supply with the decimal amount
        targetSupply = totalSupply;                             // Update total supply with the decimal amount
        balanceOf[msg.sender] = totalSupply;                    // Give the creator all initial tokens
        name = tokenName;                                       // Set the name for display purposes
        symbol = tokenSymbol;                                   // Set the name for display purposes
        auctionThreshold = tokenAuctionThreshold;               // Set the symbol for display purposes
        auctionEnded = true;
    }

    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Check if the sender has enough
        require(balanceOf[_from] >= _value);
        // Check for overflows
        require(balanceOf[_to] + _value > balanceOf[_to]);
        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        // Subtract from the sender
        balanceOf[_from] -= _value;
        // Add the same to the recipient
        balanceOf[_to] += _value;
        Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public {
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
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
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
    
    /**
     * Mint tokens
     *
     * Add `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to mint
     */
    function mint(uint256 _value, address recipient) internal returns (bool success) {
        balanceOf[recipient] += _value;             // Add to recipient
        totalSupply += _value;                      // Updates totalSupply
        Mint(recipient, _value);
        return true;
    }
    
    // auction functions
    function startAuction() public returns(bool success) {
        require(targetSupply != totalSupply, "No change in supply necessary.");
        require(auctionEnded, "Previous auction is not completed");
        if (targetSupply < totalSupply) {
            burnAuction = true;
            auctionAmount = totalSupply - targetSupply; 
        } else {
            burnAuction = false;
            auctionAmount = targetSupply - totalSupply; 
        }
        if (auctionAmount > auctionThreshold*totalSupply) { 
            auctionAmount = auctionThreshold*totalSupply;
        }
        auctionEnded = false;
        auctionEndTime = now + 3600;
        return true;
    }
    
    function endAuction() public returns(bool success) {
        require(now >= auctionEndTime, "Auction not yet ended.");
        require(!auctionEnded, "auctionEnd has already been called.");
        
        auctionEnded = true;
        emit AuctionEnded(currentBidder, currentBid);
        
        if (burnAuction) {
            totalSupply -= auctionAmount;
            Burn(msg.sender, auctionAmount);
            msg.sender.transfer(currentBid)
        } else {
            mint(currentBidder, auctionAmount);
        }
        currentBid = 0;
    }
    
    function burnBid() public payable returns(bool success) {
        require(now <= auctionEndTime, "Auction already ended.");
        require(burnAuction, "No burning necessary, use mint_bid function");
        require(msg.value < currentBid, "There already is a lower bid." );
        require(balanceOf[msg.sender] >= auctionAmount, "You do not have enough to burn");

        if (currentBid != 0) {
            pendingReturns[currentBidder] += currentBid;
            pendingTokens[currentBidder] += auctionAmount;
        }
        
        currentBidder = msg.sender;
        currentBid = msg.value;
        balanceOf[msg.sender] -= auctionAmount;
        emit CurrentBidChanged(msg.sender, msg.value);
    }
    
    function mintBid() public payable returns(bool success) {
        require(now <= auctionEndTime, "Auction already ended." );
        require(!burnAuction, "No minting necessary, use burn_bid function");
        require(msg.value > currentBid, "There already is a higher bid.");

        if (currentBid != 0) { 
            pendingReturns[currentBidder] += currentBid;
        }
        
        currentBidder = msg.sender;
        currentBid = msg.value;
        emit CurrentBidChanged(msg.sender, msg.value);
    }
    
    function reclaim() public returns (bool) {
        uint256 amount = pendingReturns[msg.sender];
        
        if (amount > 0) {
            pendingReturns[msg.sender] = 0;

            if (!msg.sender.transfer(amount)) {
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        
        amount = pendingTokens[msg.sender];
        
        if (amount > 0) {
            balanceOf[msg.sender] += amount;
            pendingTokens[msg.sender] = 0;
        }
        
        return true;
    }
    
    function vote(uint256 _value, uint256 _supplyTarget) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
        require(_supplyTarget > 0);   // Check if the sender has enough
        balanceOf[msg.sender] -= _value;            // Subtract from the sender
        targetSupply = (targetSupply*lockedSupply + _value*_supplyTarget)/(lockedSupply + _value);
        supplyTargetOf[msg.sender] = (supplyTargetOf[msg.sender]*lockedBalanceOf[msg.sender] + _value*_supplyTarget)/(lockedBalanceOf[msg.sender]+_value);
        lockedSupply += _value;
        lockedBalanceOf[msg.sender] += _value;
        Vote(msg.sender, _value, _supplyTarget);
        return true;
    }
    
    function unvote(uint256 _value) public returns (bool success) {
        require(lockedBalanceOf[msg.sender] >= _value);   // Check if the sender has enough
        lockedBalanceOf[msg.sender] -= _value;            // Subtract from the sender
        targetSupply = (targetSupply*lockedSupply - _value*supplyTargetOf[msg.sender])/(lockedSupply - _value)
        balanceOf[msg.sender] += _value;
        lockedSupply -= value;
        Unvote(msg.sender, _value);
        return true;
    }
}

