// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract AaveV3Lender is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    // The pool to deposit and withdraw through.
    IPool public constant lendingPool =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // The a Token specific rewards contract for claiming rewards.
    IRewardsController public immutable rewardsController;

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // Bool to decide to try and claim rewards. Defaults to True.
    bool public claimRewards = true;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    // to allow for reports to still work properly.
    mapping(address => uint256) public minAmountToSellMapping;

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // Mapping to be set by management for any reward tokens
    // that should not or can not be sold. This can be used
    // if selling a reward token is reverting to allow for
    // reports to still work properly.
    mapping(address => bool) public dontSell;

    constructor(
        address _asset,
        string memory _name
    ) BaseTokenizedStrategy(_asset, _name) {
        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Make sure its a real token.
        require(address(aToken) != address(0), "!aToken");

        // Set the rewards controller
        rewardsController = aToken.getIncentivesController();

        // Make approve the lending pool for cheaper deposits.
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);

        // Set uni swapper values
        // We will use the minAmountToSell mapping instead.
        minAmountToSell = 0;
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    }

    /**
     * @notice Set the uni fees for swaps.
     * @dev External function available to management to set
     * the fees used in the `UniswapV3Swapper.
     *
     * Any incentived tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /**
     * @notice Set the min amount to sell.
     * @dev External function available to management to set
     * the `minAmountToSell` variable in the `UniswapV3Swapper`.
     *
     * @param _minAmountToSell The min amount of tokens to sell.
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        lendingPool.supply(asset, _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // We dont check available liquidity because we need the tx to
        // revert if there is not enough liquidity so we dont improperly
        // pass a loss on to the user withdrawing.
        lendingPool.withdraw(
            asset,
            Math.min(aToken.balanceOf(address(this)), _amount),
            address(this)
        );
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
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            if (claimRewards) {
                // Claim and sell any rewards to `asset`.
                _claimAndSellRewards();
            }

            // deposit any loose funds
            uint256 looseAsset = ERC20(asset).balanceOf(address(this));
            if (looseAsset > 0) {
                lendingPool.supply(asset, looseAsset, address(this), 0);
            }
        }

        _totalAssets =
            aToken.balanceOf(address(this)) +
            ERC20(asset).balanceOf(address(this));
    }

    // Claim all pending reward and sell if applicable.
    function _claimAndSellRewards() internal {
        //claim all rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);

        //swap as much as possible back to want
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == asset || dontSell[token]) {
                continue;
            } else {
                uint256 balance = ERC20(token).balanceOf(address(this));

                if (balance > minAmountToSellMapping[token]) {
                    _swapFrom(token, asset, balance, 0);
                }
            }
        }
    }

    function _redeemAave() internal {
        if (!checkCooldown()) {
            return;
        }

        uint256 stkAaveBalance = ERC20(address(stkAave)).balanceOf(
            address(this)
        );

        if (stkAaveBalance > 0) {
            stkAave.redeem(address(this), stkAaveBalance);
        }

        // sell AAVE for want
        _swapFrom(AAVE, asset, ERC20(AAVE).balanceOf(address(this)), 0);
    }

    function checkCooldown() public view returns (bool) {
        if (block.chainid != 1) {
            return false;
        }

        uint256 cooldownStartTimestamp = IStakedAave(stkAave).stakersCooldowns(
            address(this)
        );

        if (cooldownStartTimestamp == 0) return false;

        uint256 COOLDOWN_SECONDS = IStakedAave(stkAave).COOLDOWN_SECONDS();
        uint256 UNSTAKE_WINDOW = IStakedAave(stkAave).UNSTAKE_WINDOW();
        if (block.timestamp >= cooldownStartTimestamp + COOLDOWN_SECONDS) {
            return
                block.timestamp - (cooldownStartTimestamp + COOLDOWN_SECONDS) <=
                UNSTAKE_WINDOW;
        } else {
            return false;
        }
    }

    function _harvestStkAave() internal {
        // request start of cooldown period
        if (ERC20(address(stkAave)).balanceOf(address(this)) > 0) {
            stkAave.cooldown();
        }
    }

    function manualRedeemAave() external onlyKeepers {
        _redeemAave();
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        return ERC20(asset).balanceOf(address(aToken));
    }

    /**
     * @notice Allows `management` to manually swap a token the strategy holds.
     * @dev This can be used if the rewards controller has since removed a reward
     * token so the normal harvest flow doesnt work. Or for retroactive airdrops.
     * @param _token The address of the token to sell.
     */
    function sellRewardManually(
        address _token,
        uint256 _minAmountOut
    ) external onlyManagement {
        uint256 balance = ERC20(_token).balanceOf(address(this));
        // Swap from will do min check
        _swapFrom(_token, asset, balance, _minAmountOut);
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _calimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
    }

    /**
     * @notice Set wether or not the strategy should claim and sell rewards.
     * @param _bool Wether or not rewards should be claimed and sold
     */
    function setClaimRewards(bool _bool) external onlyManagement {
        claimRewards = _bool;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A seperate
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
        lendingPool.withdraw(
            asset,
            Math.min(_amount, aToken.balanceOf(address(this))),
            address(this)
        );
    }
}
