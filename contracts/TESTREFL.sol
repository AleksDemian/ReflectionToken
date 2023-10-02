// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.18;

interface IFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IDistributor {
    function setShare(address shareholder, uint256 amount) external;

    function process(uint256 gas) external;

    function getShareholders() external view returns (address[] memory);

    function getShareForHolder(address holder) external view returns (uint256);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library Address {
    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

/**
 * @title TESTREFL
 * @notice Implementation of the reflective token contract
 */
contract TESTREFL is Context, IERC20, Ownable {
    using Address for address payable;

    /// @notice Amount of tokens in the r-space
    mapping(address => uint256) private _rOwned;
    /// @notice Amount of tokens in the t-space
    mapping(address => uint256) private _tOwned;
    /// @notice Amount of tokens that are allowed to be transferred
    mapping(address => mapping(address => uint256)) private _allowances;
    /// @notice Addresses that are excluded from the fee
    mapping(address => bool) private _isExcludedFromFee;
    /// @notice Addresses that are excluded from the reward
    mapping(address => bool) private _isExcluded;

    mapping(address => bool) private _isTxLimitExempt;
    mapping(address => bool) public isLiquidityPool;

    /// @notice Array of excluded addresses
    address[] private _excluded;

    /// @notice ETH -> Main
    address[] path;

    /// @notice Allowing or blocking the swap
    bool private swapping;

    /// @notice Enable automatic conversion to marketing wallet
    bool public swapEnabled = true;

    /// @notice Address of router interface
    IRouter public router;
    /// @notice Address of pair
    address public pair;

    /// @notice Decimals of the token
    uint8 private constant _decimals = 18;
    /// @notice The max value in the type of uint256
    uint256 private constant MAX = ~uint256(0);

    /// @notice Total supply of token in t-space
    uint256 private _tTotal = 10e9 * 10 ** _decimals; // 10e9 = 10 000 000 000
    /// @notice Total supply of token in r-space
    uint256 private _rTotal = (MAX - (MAX % _tTotal));

    uint256 private _totalReflections; // Total reflections

    /// @notice Trigger to start token swapping for marketing
    uint256 public swapTokensAtAmount = 1e6 * 10 ** _decimals; // 1e6 = 1 000 000

    /// @notice Address of wallet for burning
    address public deadWallet = 0x000000000000000000000000000000000000dEaD;
    /// @notice Address of wallet for marketing
    address public marketingWallet = 0x75001CCDa5B6a711546D9BC14Ac805Dd78Ccc24f;

    /// @notice Name of token
    string private constant _name = "TEST REFL";
    /// @notice Symbol of token
    string private constant _symbol = "TESTREFL";

    /// @notice Structure for information about fee
    struct Taxes {
        uint256 rfi;
        uint256 marketing;
    }
    // Tax 1% reflection, 3% marketing
    Taxes public taxes = Taxes(1, 3);

    /// @notice Structure for information about total paid fees
    struct TotFeesPaidStruct {
        uint256 rfi;
        uint256 marketing;
    }

    TotFeesPaidStruct public totFeesPaid;

    // Token Limits
    uint256 public _maxTxAmount = _tTotal / (100); // 10 million
    uint256 public _tokenSwapThreshold = _tTotal / (200); // 5 million

    // gas for distributor
    IDistributor _distributor;
    uint256 _distributorGas = 500000;

    /// @notice Structure for information about values in r-space and t-space
    struct valuesFromGetValues {
        uint256 rAmount; // tokens transferred in the r-space
        uint256 rTransferAmount; // tokens transferred in the r-space deducting fees
        uint256 rRfi; // reflection fees  in r-space
        uint256 rMarketing; // marketing fees in r-space
        uint256 tTransferAmount; // tokens transferred in the t-space deducting fees
        uint256 tRfi; // reflection fees in t-space
        uint256 tMarketing; // marketing fees in t-space
    }

    /// @dev Blocks the ability to swap until the function is executed
    modifier lockTheSwap() {
        swapping = true;
        _;
        swapping = false;
    }

    /**
     * @dev Initializes the contract
     * @param routerAddress address of uniswap V2 router
     */
    constructor(address routerAddress, address distributor) {
        // Create a uniswap pair for this new token
        IRouter _router = IRouter(routerAddress);
        address _pair = IFactory(_router.factory()).createPair(
            address(this),
            _router.WETH()
        );

        router = _router;
        pair = _pair;

        // Set Distributor
        _distributor = IDistributor(distributor);

        // Exclusions from staking to fully reward users.
        excludeFromReward(pair);
        excludeFromReward(deadWallet);
        excludeFromReward(address(this));

        // tx limit exclusions
        _isTxLimitExempt[msg.sender] = true;
        _isTxLimitExempt[address(this)] = true;

        // liquidity pools
        isLiquidityPool[_pair] = true;

        path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        // Minting tokens to owner in r-space
        _rOwned[owner()] = _rTotal;

        // Exclusion of technical addresses from the fee
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[marketingWallet] = true;
        _isExcludedFromFee[deadWallet] = true;

        emit Transfer(address(0), owner(), _tTotal);
    }

    /// @return Name of created token
    function name() public pure returns (string memory) {
        return _name;
    }

    /// @return Symbol of created token
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    /// @return Decimals of created token
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    /// @return Total supply of created token
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function setIsLiquidityPool(address pool, bool isPool) external onlyOwner {
        isLiquidityPool[pool] = isPool;
        emit SetIsLiquidityPool(pool, isPool);
    }

    /**
     * @notice Shows the user's balance
     * @param account user's addresses
     * @return If the address is excluded from rewards, it returns the value
     * in t-space, otherwise it converts the value from r-space
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /**
     * @notice Shows the allowance to transfer tokens from the owner to the spender
     * @param _owner address of the token owner
     * @param _spender address of the token spender
     * @return amount of tokens that can be used by spender
     */
    function allowance(
        address _owner,
        address _spender
    ) public view override returns (uint256) {
        return _allowances[_owner][_spender];
    }

    /**
     * @notice Allows the spender to transfer tokens
     * @param spender address of the token spender
     * @param amount amount of the tokens
     * @return Returns the approval status
     */
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @notice Transfers tokens from the sender to the recipient, changing its allowance
     * @param sender address of the tokens sender
     * @param recipient address of the tokens recipient
     * @param amount amount of the tokens
     * @return Returns the transfer status
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        _approve(sender, _msgSender(), currentAllowance - amount);

        _transfer(sender, recipient, amount);
        return true;
    }

    /**
     * @notice Increase the allowance to transfer tokens from the owner to the spender
     * @param spender address of the tokens spender
     * @param addedValue value of tokens to add
     * @return Returns the status of increasing approval
     */
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    /**
     * @notice Decrease the allowance to transfer tokens from the owner to the spender
     * @param spender address of the tokens spender
     * @param subtractedValue value of tokens to subtract
     * @return Returns the status of decreasing approval
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    /**
     * @notice Transfer tokens to the recipient
     * @param recipient address of the tokens recipient
     * @param amount value of tokens to transfer
     * @return Returns the transfer status
     */
    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @notice Checks if the user is excluded from rewards
     * @param account user address
     * @return Status of user
     */
    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    /**
     * @notice Сonverts tokens from t-space to r-space
     * @param tAmount value of tokens in t-space to convert
     * @param deductTransferRfi Determines if the transfer fee should be deducted
     * @return Returns tokens amount in r-space
     */
    function reflectionFromToken(
        uint256 tAmount,
        bool deductTransferRfi
    ) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferRfi) {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rAmount;
        } else {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rTransferAmount;
        }
    }

    /**
     * @notice Сonverts tokens from r-space to t-space
     * @param rAmount value of tokens in r-space to convert
     * @return Returns amount of tokens in t-space at the current rate
     */
    function tokenFromReflection(
        uint256 rAmount
    ) public view returns (uint256) {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    /**
     * @notice Moves user tokens to t-space and excludes him from rewards
     * @param account user address
     * @dev Сan be executed only by the owner
     */
    function excludeFromReward(address account) public onlyOwner {
        require(account != address(this) && account != pair);
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
        _distributor.setShare(account, 0);
        emit ExcludeFromRewards(account);
    }

    /**
     * @notice Includes the user in the reward, removing him from the excluded array
     * @param account user address
     * @dev Сan be executed only by the owner
     */
    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                // updating _rOwned to make sure the balances stay the same
                if (_tOwned[account] > 0) {
                    uint256 newrOwned = _tOwned[account] * (_getRate());
                    _rTotal = _rTotal - (_rOwned[account] - newrOwned);
                    _totalReflections =
                        _totalReflections +
                        (_rOwned[account] - newrOwned);
                    _rOwned[account] = newrOwned;
                } else {
                    _rOwned[account] = 0;
                }

                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
        _distributor.setShare(account, balanceOf(account));
        emit IncludeInRewards(account);
    }

    function setDistributorGas(uint256 gas) external onlyOwner {
        require(gas < 10000000);
        _distributorGas = gas;
        emit SetDistributorGas(gas);
    }

    function setFeeExemption(
        address account,
        bool feeExempt
    ) external onlyOwner {
        _isExcludedFromFee[account] = feeExempt;
        emit SetFeeExemption(account, feeExempt);
    }

    function setTxLimitExempt(
        address account,
        bool isExempt
    ) external onlyOwner {
        _isTxLimitExempt[account] = isExempt;
        emit SetTxLimitFeeExemption(account, isExempt);
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        _maxTxAmount = maxTxAmount;
        emit SetMaxTxAmount(maxTxAmount);
    }

    function upgradeDistributor(address newDistributor) external onlyOwner {
        require(newDistributor != address(0));
        _distributor = IDistributor(newDistributor);
        emit UpgradedDistributor(newDistributor);
    }

    function setTokenSwapThreshold(
        uint256 tokenSwapThreshold
    ) external onlyOwner {
        require(tokenSwapThreshold > 0);
        _tokenSwapThreshold = tokenSwapThreshold;
        emit SetTokenSwapThreshold(tokenSwapThreshold);
    }

    function getTotalReflections() external view returns (uint256) {
        return _totalReflections;
    }

    function isTxLimitExempt(address account) external view returns (bool) {
        return _isTxLimitExempt[account];
    }

    function getDistributorAddress() external view returns (address) {
        return address(_distributor);
    }

    /**
     * @notice Checks if the user is excluded from fee
     * @param account user address
     * @return Status of user
     */
    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    /**
     * @notice Deflationary mechanism that makes tokens in r-space more valuable
     * @param rRfi the value of the reflection fee in r-space
     * @param tRfi the value of the reflection fee in t-space
     */
    function _reflectRfi(uint256 rRfi, uint256 tRfi) private {
        _rTotal -= rRfi; // reduces total supply of tokens in the r-space after each transaction
        totFeesPaid.rfi += tRfi;
    }

    /**
     * @notice Collects marketing fees at the token address
     * @param rMarketing the value of the marketing fee in r-space
     * @param tMarketing the value of the marketing fee in t-space
     */
    function _takeMarketing(uint256 rMarketing, uint256 tMarketing) private {
        totFeesPaid.marketing += tMarketing;

        if (_isExcluded[address(this)]) {
            _tOwned[address(this)] += tMarketing;
        }
        _rOwned[address(this)] += rMarketing; // marketing fees are accumulated on the token contract
    }

    /**
     * @notice Fills the value for the structure
     * @param tAmount the value of tokens in t-space
     * @param takeFee trigger for collecting fees
     * @return to_return filled structure of values for the transfer
     */
    function _getValues(
        uint256 tAmount,
        bool takeFee
    ) private view returns (valuesFromGetValues memory to_return) {
        to_return = _getTValues(tAmount, takeFee);
        (
            to_return.rAmount,
            to_return.rTransferAmount,
            to_return.rRfi,
            to_return.rMarketing
        ) = _getRValues(to_return, tAmount, takeFee, _getRate());

        return to_return;
    }

    /**
     * @notice Fills the value for the structure in t-space
     * @param tAmount the value of tokens in t-space
     * @param takeFee trigger for collecting fees
     * @return s filled values for the transfer in t-space
     */
    function _getTValues(
        uint256 tAmount,
        bool takeFee
    ) private view returns (valuesFromGetValues memory s) {
        if (!takeFee) {
            s.tTransferAmount = tAmount;
            return s;
        }

        s.tRfi = (tAmount * taxes.rfi) / 100;
        s.tMarketing = (tAmount * taxes.marketing) / 100;
        s.tTransferAmount = tAmount - s.tRfi - s.tMarketing;
        return s;
    }

    /**
     * @notice Fills the value for the structure in r-space
     * @param s structure with filled t-space values
     * @param tAmount the value of tokens in t-space
     * @param takeFee trigger for collecting fees
     * @param currentRate current rate for conversion
     * @return rAmount tokens transferred in the r-space
     * @return rTransferAmount tokens transferred in the r-space deducting fees
     * @return rRfi reflection fees in r-space
     * @return rMarketing marketing fees in r-space
     */
    function _getRValues(
        valuesFromGetValues memory s,
        uint256 tAmount,
        bool takeFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rRfi,
            uint256 rMarketing
        )
    {
        rAmount = tAmount * currentRate;

        if (!takeFee) {
            return (rAmount, rAmount, 0, 0);
        }

        rRfi = s.tRfi * currentRate;
        rMarketing = s.tMarketing * currentRate;
        rTransferAmount = rAmount - rRfi - rMarketing;
        return (rAmount, rTransferAmount, rRfi, rMarketing);
    }

    /**
     * @notice Сalculates the current rate
     * @return the ratio of supply r-space tokens to t-space
     */
    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    /**
     * @notice Calculates the current token supply by subtracting the tokens of excluded addresses
     * @return Current supply of r-space and t-space tokens
     */
    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function getIncludedTotalSupply() external view returns (uint256) {
        (, uint256 tSupply) = _getCurrentSupply();
        return tSupply;
    }

    /**
     * @notice Allows the spender to transfer tokens
     * @param _owner address of the token owner
     * @param _spender address of the token spender
     * @param _amount amount of the tokens
     */
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");
        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /**
     * @notice Checking all conditions before the transfer
     * @param from address of the tokens sender
     * @param to address of the tokens recipient
     * @param amount value of tokens to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            amount <= balanceOf(from),
            "You are trying to transfer more than your balance"
        );
        require(amount <= _maxTxAmount || _isTxLimitExempt[from], "TX Limit");

        if (swapping) {
            // tokens being sent to Router or marketing
            _tokenTransfer(from, to, amount, false);
            return true;
        }

        bool takeFee = !(_isExcludedFromFee[from] || _isExcludedFromFee[to]);
        // /**
        //  * When the balance on the token contract exceeds the trigger amount,
        //  * the swap is triggered and sent to marketing
        //  */
        // bool canSwap = balanceOf(address(this)) >= swapTokensAtAmount;
        // if (
        //     swapEnabled &&
        //     !swapping &&
        //     canSwap &&
        //     from != pair &&
        //     !_isExcludedFromFee[from] &&
        //     !_isExcludedFromFee[to]
        // ) {
        //     swapAndSendToMarketing();
        // }

        // the status of fees withdrawal is set
        // bool takeFee = true;
        // if (swapping || _isExcludedFromFee[from] || _isExcludedFromFee[to])
        //     takeFee = false;

        // Should Swap For BNB
        if (shouldSwapBack(from)) {
            // Fuel distributors
            swapBack(_tokenSwapThreshold, takeFee);
            // transfer token
            _tokenTransfer(from, to, amount, takeFee);
        } else {
            // transfer token
            _tokenTransfer(from, to, amount, takeFee);
            // process dividends
            try _distributor.process(_distributorGas) {} catch {}
        }

        // update distributor values
        if (!_isExcluded[from]) {
            _distributor.setShare(from, balanceOf(from));
        }
        if (!_isExcluded[to]) {
            _distributor.setShare(to, balanceOf(to));
        }
        return true;
        // _tokenTransfer(from, to, amount, takeFee);
    }

    /** Should Contract Sell Down Tokens For BNB */
    function shouldSwapBack(address from) public view returns (bool) {
        return
            balanceOf(address(this)) >= _tokenSwapThreshold &&
            !swapping &&
            from != pair;
    }

    function swapBack(uint256 tokenAmount, bool takeFee) private lockTheSwap {
        valuesFromGetValues memory s = _getValues(tokenAmount, takeFee);

        // tokens for marketing
        uint256 marketingAmount = tokenAmount * (_marketingFee).div(10 ** 2);

        // transfer from this to marketing, ignoring fees
        _tokenTransfer(address(this), marketingWallet, marketingAmount, false);

        // update distributor
        if (!_isExcluded[marketingWallet]) {
            _distributor.setShare(marketingWallet, balanceOf(marketingWallet));
        }

        // update token amount to swap
        uint256 swapAmount = tokenAmount.sub(marketingAmount);

        // Swap tokens for ETH
        swapTokensForETH(swapAmount);

        // Send ETH received to the distributor
        if (address(this).balance > 0) {
            (bool success, ) = payable(address(_distributor)).call{
                value: address(this).balance
            }("");
            require(success, "Failure on Distributor Payment");
        }

        emit SwappedBack(tokenAmount);
    }

    /**
     * @notice Transfer of tokens including fees
     * @param sender address of the tokens sender
     * @param recipient address of the tokens recipient
     * @param tAmount value of tokens to transfer in t-space
     * @param takeFee status of fees withdrawal
     */
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee
    ) private {
        // Fill in the structure of transfer values and fees
        valuesFromGetValues memory s = _getValues(tAmount, takeFee);

        if (_isExcluded[sender]) {
            // From excluded
            _tOwned[sender] = _tOwned[sender] - tAmount;
        }
        if (_isExcluded[recipient]) {
            // To excluded
            _tOwned[recipient] = _tOwned[recipient] + s.tTransferAmount;
        }

        _rOwned[sender] = _rOwned[sender] - s.rAmount;
        _rOwned[recipient] = _rOwned[recipient] + s.rTransferAmount;

        // Deflationary mechanism is activated
        if (s.rRfi > 0 || s.tRfi > 0) _reflectRfi(s.rRfi, s.tRfi);

        // Collects marketing fees at the token contract address
        if (s.rMarketing > 0 || s.tMarketing > 0)
            _takeMarketing(s.rMarketing, s.tMarketing);

        emit Transfer(sender, recipient, s.tTransferAmount);
    }

    /**
     * @notice Take balance of token contract, convert it to ETH and send it to the marketing wallet
     * @dev when executing the function, the ability to swap is blocked
     */
    function swapAndSendToMarketing() private lockTheSwap {
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForETH(contractBalance);
        uint256 deltaBalance = address(this).balance;

        if (deltaBalance > 0) {
            payable(marketingWallet).sendValue(deltaBalance);
        }
    }

    /**
     * @notice Convert tokens to ETH on pancakeswap router
     * @param tokenAmount amount of tokens to be converted
     */
    function swapTokensForETH(uint256 tokenAmount) private {
        // address[] memory path = new address[](2);
        // path[0] = address(this);
        // path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @notice Exclusion of several addresses from the commission at once
     * @param accounts array of user's addresses
     * @param state status of exclusion
     * @dev Сan be executed only by the owner
     */
    function bulkExcludeFee(
        address[] memory accounts,
        bool state
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = state;
        }
    }

    /**
     * @notice Enable(true) or disable(false) automatic conversion
     * @dev Сan be executed only by the owner
     */
    function updateSwapEnabled(bool newVal) external onlyOwner {
        swapEnabled = newVal;
    }

    /**
     * @notice Update the marketing wallet address
     * @param newWallet new marketing wallet address
     * @dev Сan be executed only by the owner
     */
    function updateMarketingWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Fee Address cannot be zero address");
        marketingWallet = newWallet;
    }

    /**
     * @notice Update swap threshold amount
     * @param amount value of token
     * @dev Сan be executed only by the owner
     */
    function updateSwapTokensAtAmount(uint256 amount) external onlyOwner {
        require(
            amount <= 1e8,
            "Cannot set swap threshold amount higher than 1% of tokens"
        );
        swapTokensAtAmount = amount * 10 ** _decimals;
    }

    /**
     * @notice Recover ETH sent to the contract address by mistake
     * @param weiAmount amount of ETH
     * @dev Сan be executed only by the owner
     */
    function recoverETH(uint256 weiAmount) external onlyOwner {
        require(address(this).balance >= weiAmount, "insufficient ETH balance");
        payable(msg.sender).transfer(weiAmount);
    }

    /**
     * @notice Recover any ERC20 tokens sent to the contract address by mistake
     * @param _tokenAddr ERC20 token address
     * @param _to tokens recipient
     * @param _amount amount of tokens
     * @dev Сan be executed only by the owner
     */
    function recoverAnyERC20Tokens(
        address _tokenAddr,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        require(
            _tokenAddr != address(this),
            "Owner can't claim contract's balance of its own tokens"
        );
        IERC20(_tokenAddr).transfer(_to, _amount);
    }

    receive() external payable {}

    event SwappedBack(uint256 swapAmount);
    event FeesDistributed(
        uint256 burnPortion,
        uint256 reflectPortion,
        uint256 distributorPortion
    );
    event TransferOwnership(address newOwner);
    event OwnerWithdraw(address token, uint256 amount);
    event UpdatedRouterAddress(address newRouter);
    event UpdatedPairAddress(address newPair);
    event SetIsLiquidityPool(address pool, bool isPool);
    event ExcludeFromRewards(address account);
    event SetFeeExemption(address account, bool feeExempt);
    event SetTxLimitFeeExemption(address account, bool txLimitExempt);
    event SetMaxTxAmount(uint256 newAmount);
    event UpgradedDistributor(address newDistributor);
    event SetTokenSwapThreshold(uint256 tokenSwapThreshold);
    event SetMarketingAddress(address marketingAddress);
    event SetFees(
        uint256 burnFee,
        uint256 reflectFee,
        uint256 reflectbabyFee,
        uint256 marketingFee,
        uint256 buyFee,
        uint256 transferFee
    );
    event IncludeInRewards(address account);
    event SetDistributorGas(uint256 gas);
}
