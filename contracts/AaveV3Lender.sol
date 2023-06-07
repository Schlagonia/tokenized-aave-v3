// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "./interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract AaveV3Lender is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    IProtocolDataProvider public constant protocolDataProvider =
        IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);
    IPool public immutable lendingPool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // stkAave addresses only Applicable for Mainnet.
    IStakedAave internal constant stkAave =
        IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    constructor(
        address _asset,
        string memory _name
    ) BaseTokenizedStrategy(_asset, _name) {
        lendingPool = IPool(
            protocolDataProvider.ADDRESSES_PROVIDER().getPool()
        );
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        require(address(aToken) != address(0), "!aToken");

        rewardsController = aToken.getIncentivesController();

        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);

        // Set uni swapper values
        minAmountToSell = 1e4;
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    }

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

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
        // Claim and sell any rewards to `asset`.
        _claimAndSellRewards();

        // deposit any loose funds
        uint256 looseAsset = ERC20(asset).balanceOf(address(this));
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            lendingPool.supply(asset, looseAsset, address(this), 0);
        }

        _totalAssets =
            aToken.balanceOf(address(this)) +
            ERC20(asset).balanceOf(address(this));
    }

    function _claimAndSellRewards() internal {
        // Need to redeem any aave from StkAave if applicable before
        // claiming rewards and staring cool down over
        _redeemAave();

        //claim all rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);

        //swap as much as possible back to want
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == address(stkAave)) {
                _harvestStkAave();
            } else if (token == asset) {
                continue;
            } else {
                _swapFrom(
                    token,
                    asset,
                    ERC20(token).balanceOf(address(this)),
                    0
                );
            }
        }
    }

    function _redeemAave() internal {
        if (!_checkCooldown()) {
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

    function _checkCooldown() internal view returns (bool) {
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
        lendingPool.withdraw(asset, _amount, address(this));
    }
}
