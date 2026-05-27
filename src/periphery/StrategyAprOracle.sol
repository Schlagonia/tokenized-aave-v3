// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

import {IAToken} from "../interfaces/Aave/V3/IAtoken.sol";
import {IPool, DataTypesV3} from "../interfaces/Aave/V3/IPool.sol";
import {IRewardsController} from "../interfaces/Aave/V3/IRewardsController.sol";
import {IProtocolDataProvider} from "../interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IReserveInterestRateStrategy} from "../interfaces/Aave/V3/IReserveInterestRateStrategy.sol";

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

contract StrategyAprOracle {
    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    address internal immutable WNATIVE;

    IUniswapV2Router02 public immutable ROUTER;

    constructor(address _wNative, address _router) {
        WNATIVE = _wNative;
        ROUTER = IUniswapV2Router02(_router);
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta) external view returns (uint256) {
        address asset = IStrategyInterface(_strategy).asset();
        address aToken = IStrategyInterface(_strategy).A_TOKEN();
        IPool lendingPool = IPool(IStrategyInterface(_strategy).LENDING_POOL());
        IProtocolDataProvider protocolDataProvider =
            IProtocolDataProvider(lendingPool.ADDRESSES_PROVIDER().getPoolDataProvider());

        (uint256 newLiquidityRate, uint256 totalAToken) =
            _getNewLiquidityRate(asset, aToken, lendingPool, protocolDataProvider, _delta);

        uint256 rewardsRate;
        if (IStrategyInterface(_strategy).claimRewards()) {
            rewardsRate = getRewardApr(_strategy, asset, _applyDebtDelta(totalAToken, _delta));
        }

        return newLiquidityRate / 1e9 + rewardsRate; // divided by 1e9 to go from Ray to Wad
    }

    function _getNewLiquidityRate(
        address _asset,
        address _aToken,
        IPool _lendingPool,
        IProtocolDataProvider _protocolDataProvider,
        int256 _delta
    ) internal view returns (uint256, uint256 totalAToken) {
        DataTypesV3.CalculateInterestRatesParams memory params;

        (
            params.unbacked,,
            totalAToken,
            params.totalStableDebt,
            params.totalVariableDebt,,,,
            params.averageStableBorrowRate,,,
        ) = _protocolDataProvider.getReserveData(_asset);

        (,,,, params.reserveFactor,,,,,) = _protocolDataProvider.getReserveConfigurationData(_asset);

        params.liquidityAdded = _delta > 0 ? uint256(_delta) : 0;
        params.liquidityTaken = _delta < 0 ? uint256(-1 * _delta) : 0;
        params.reserve = _asset;
        params.aToken = _aToken;

        (uint256 newLiquidityRate,,) = IReserveInterestRateStrategy(
                _lendingPool.getReserveData(_asset).interestRateStrategyAddress
            ).calculateInterestRates(params);

        return (newLiquidityRate, totalAToken);
    }

    function getRewardApr(address _strategy, address _asset, uint256 _underlyingBalance) public view returns (uint256) {
        if (_underlyingBalance == 0) return 0;

        IAToken aToken = IAToken(IStrategyInterface(_strategy).A_TOKEN());
        IRewardsController rewardsController = IRewardsController(aToken.getIncentivesController());

        address[] memory rewardTokens = rewardsController.getRewardsByAsset(address(aToken));
        uint256 i;
        uint256 tokenIncentivesRate;
        // Passes total supply and the corresponding reward token for each reward token.
        for (i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            if (rewardToken == address(0)) return 0;

            if (block.timestamp < rewardsController.getDistributionEnd(address(aToken), rewardToken)) {
                uint256 emissionsPerSecond;
                (, emissionsPerSecond,,) = rewardsController.getRewardsData(address(aToken), rewardToken);
                if (emissionsPerSecond > 0) {
                    uint256 emissionsInAsset;
                    if (rewardToken == _asset || rewardToken == address(aToken)) {
                        emissionsInAsset = emissionsPerSecond;
                    } else {
                        emissionsInAsset = _checkPrice(rewardToken, _asset, emissionsPerSecond);
                    }

                    tokenIncentivesRate += (emissionsInAsset * SECONDS_IN_YEAR * 1e18) / _underlyingBalance;
                }
            }
        }
        return (tokenIncentivesRate * 9_500) / 10_000;
    }

    function _applyDebtDelta(uint256 _underlyingBalance, int256 _delta) internal pure returns (uint256) {
        if (_delta >= 0) return _underlyingBalance + uint256(_delta);

        uint256 decrease = uint256(-1 * _delta);
        if (decrease >= _underlyingBalance) return 0;
        return _underlyingBalance - decrease;
    }

    function _checkPrice(address start, address end, uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        try ROUTER.getAmountsOut(_amount, getTokenOutPath(start, end)) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isNative = _tokenIn == WNATIVE || _tokenOut == WNATIVE;
        _path = new address[](isNative ? 2 : 3);
        _path[0] = _tokenIn;

        if (isNative) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = WNATIVE;
            _path[2] = _tokenOut;
        }
    }
}
