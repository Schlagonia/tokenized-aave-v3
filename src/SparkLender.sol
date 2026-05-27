// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";

// Swappers
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

contract SparkLender is BaseHealthCheck, UniswapV3Swapper, AuctionSwapper {
    using SafeERC20 for ERC20;

    // To get the Supply cap of an asset.
    uint256 internal constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal immutable decimals;

    // The pool to deposit and withdraw through.
    IPool public immutable lendingPool;

    // The a Token specific rewards contract for claiming rewards.
    IRewardsController public immutable rewardsController;

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // Bool to decide to try and claim rewards. Defaults to False.
    bool public claimRewards;

    constructor(address _asset, string memory _name, address _lendingPool, address _router, address _base)
        BaseHealthCheck(_asset, _name)
    {
        lendingPool = IPool(_lendingPool);

        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Get aToken decimals for supply caps.
        decimals = ERC20(address(aToken)).decimals();

        // Set the rewards controller
        rewardsController = aToken.getIncentivesController();

        // Make approve the lending pool for cheaper deposits.
        asset.safeApprove(address(lendingPool), type(uint256).max);

        // Set uni swapper values.
        router = _router;
        base = _base;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        lendingPool.supply(address(asset), _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        lendingPool.withdraw(address(asset), Math.min(aToken.balanceOf(address(this)), _amount), address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (claimRewards) {
            // Claim and sell any rewards to `asset`.
            _claimAndSellRewards();
        }

        _totalAssets = aToken.balanceOf(address(this)) + balanceOfAsset();
    }

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Used to claim any pending rewards and sell them to asset.
     */
    function _claimAndSellRewards() internal {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList,) = rewardsController.claimAllRewardsToSelf(assets);

        // If using the Auction contract we are done.
        if (useAuction) return;

        // Else swap as much as possible back to asset through uni.
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == address(asset) || token == address(aToken)) {
                continue;
            }

            uint256 balance = ERC20(token).balanceOf(address(this));

            if (balance > minAmountToSell[token]) {
                _swapFrom(token, address(asset), balance, 0);
            }
        }
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     */
    function availableDepositLimit(address _owner) public view override returns (uint256) {
        uint256 baseLimit = super.availableDepositLimit(_owner);
        if (baseLimit == 0) return 0;

        // Get the data configuration bitmap.
        uint256 _data = lendingPool.getConfiguration(address(asset)).data;

        // Cannot deposit when paused or frozen.
        if (_isPaused(_data) || _isFrozen(_data)) return 0;

        uint256 supplyCap = _getSupplyCap(_data);

        // If we have no supply cap.
        if (supplyCap == 0) return baseLimit;

        // Supply plus any already idle funds.
        uint256 supply = aToken.totalSupply() + asset.balanceOf(address(this));

        // If we already hit the cap.
        if (supplyCap <= supply) return 0;

        // Return the remaining room.
        unchecked {
            return Math.min(baseLimit, supplyCap - supply);
        }
    }

    /**
     * @notice Gets the supply cap of the reserve
     * @return The supply cap
     */
    function getSupplyCap() public view returns (uint256) {
        return _getSupplyCap(lendingPool.getConfiguration(address(asset)).data);
    }

    /**
     * @dev Given the data configuration returns the supply cap.
     */
    function _getSupplyCap(uint256 _data) internal view returns (uint256) {
        // Get out the supply cap for the asset.
        uint256 cap = (_data & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
        // Adjust to the correct decimals.
        return cap * (10 ** decimals);
    }

    /**
     * @dev Paused flag is at the 60th bit
     */
    function _isPaused(uint256 _data) internal pure returns (bool) {
        // Create a mask with only the 60th bit set
        uint256 mask = 1 << 60; // Bitwise left shift by 60 positions

        // Perform bitwise AND operation to check if the 60th bit is 0.
        return (_data & mask) != 0;
    }

    /**
     * @dev Frozen flag is at the 57th bit.
     */
    function _isFrozen(uint256 _data) internal pure returns (bool) {
        // Create a mask with only the 57th bit set
        uint256 mask = 1 << 57; // Bitwise left shift by 57 positions

        // Perform bitwise AND operation to check if the 57th bit 0.
        return (_data & mask) != 0;
    }

    /**
     * @dev Gets the liquid balance that can be withdrawn from the pool
     */
    function _getLiquidity() internal view returns (uint256) {
        return asset.balanceOf(address(aToken));
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address /*_owner*/
    )
        public
        view
        override
        returns (uint256)
    {
        uint256 liquidity;

        // Cannot withdraw from the pool when paused.
        if (!_isPaused(lendingPool.getConfiguration(address(asset)).data)) {
            liquidity = _getLiquidity();
        }
        return balanceOfAsset() + liquidity;
    }

    function setMinAmountToSell(address _token, uint256 _amount) external onlyManagement {
        _setMinAmountToSell(_token, _amount);
    }

    /**
     * @notice Set the uni fees for swaps.
     * @dev External function available to management to set
     * the fees used in the `UniswapV3Swapper.
     *
     * Any incentivized tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(address _token0, address _token1, uint24 _fee) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setBase(address _base) external onlyManagement {
        base = _base;
    }

    /**
     * @notice Set wether or not the strategy should claim and sell rewards.
     * @param _bool Wether or not rewards should be claimed and sold
     */
    function setClaimRewards(bool _bool) external onlyManagement {
        claimRewards = _bool;
    }

    ///////////// DUTCH AUCTION FUNCTIONS \\\\\\\\\\\\\\\\\\

    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            require(Auction(_auction).want() == address(asset), "wrong want");
        }
        _setAuction(_auction);
    }

    function kickAuction(address _token) external virtual override onlyKeepers returns (uint256 _kicked) {
        require(kickable(_token) >= minAmountToSell[_token], "too little");
        _kicked = _kickAuction(_token);
    }

    function protectedTokens() public view virtual override returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = address(asset);
        tokens[1] = address(aToken);
        return tokens;
    }

    /**
     * @notice Set if tokens should be sold through the dutch auction contract.
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        _setUseAuction(_useAuction);
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(Math.min(_getLiquidity(), _amount));
    }
}
