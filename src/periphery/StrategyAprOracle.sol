// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

import {IAToken} from "../interfaces/Aave/V3/IAtoken.sol";
import {IPool, DataTypesV3} from "../interfaces/Aave/V3/IPool.sol";
import {IRewardsController} from "../interfaces/Aave/V3/IRewardsController.sol";
import {IProtocolDataProvider} from "../interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IReserveInterestRateStrategy} from "../interfaces/Aave/V3/IReserveInterestRateStrategy.sol";

interface IUniswapV2Router02 {
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

contract StrategyAprOracle {
    address internal constant stkAave =
        address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE =
        address(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    uint256 internal constant VIRTUAL_ACC_ACTIVE_MASK = 0xEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    uint256 internal constant SECONDS_IN_YEAR = 365 days;

    address internal immutable WNATIVE;

    IUniswapV2Router02 public immutable router;

    constructor(address _wNative, address _router) {
        WNATIVE = _wNative;
        router = IUniswapV2Router02(_router);
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
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256) {
        address asset = IStrategyInterface(_strategy).asset();
        IPool lendingPool = IPool(IStrategyInterface(_strategy).lendingPool());
        IProtocolDataProvider protocolDataProvider = IProtocolDataProvider(
            lendingPool.ADDRESSES_PROVIDER().getPoolDataProvider()
        );

        //need to calculate new supplyRate after Deposit (when deposit has not been done yet)
        uint256 balance = lendingPool.getVirtualUnderlyingBalance(asset);

        (
            uint256 unbacked,
            ,
            ,
            ,
            uint256 totalVariableDebt,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = protocolDataProvider.getReserveData(asset);

        (, , , , uint256 reserveFactor, , , , , ) = protocolDataProvider
            .getReserveConfigurationData(asset);

        DataTypesV3.CalculateInterestRatesParams memory params = DataTypesV3
            .CalculateInterestRatesParams(
                unbacked + lendingPool.getReserveDeficit(asset),
                _delta > 0 ? uint256(_delta) : 0,
                _delta < 0 ? uint256(-1 * _delta) : 0,
                totalVariableDebt,
                reserveFactor,
                asset,
                true,
                balance
            );

        (uint256 newLiquidityRate, ) = IReserveInterestRateStrategy(
            lendingPool.getReserveData(asset).interestRateStrategyAddress
        ).calculateInterestRates(params);

        uint256 rewardsRate;
        if (IStrategyInterface(_strategy).claimRewards()) {
            rewardsRate = getRewardApr(
                _strategy,
                asset,
                uint256(int256(balance + totalVariableDebt) + _delta)
            );
        }

        return newLiquidityRate / 1e9 + rewardsRate; // divided by 1e9 to go from Ray to Wad
    }

    function getRewardApr(
        address _strategy,
        address _asset,
        uint256 _underlyingBalance
    ) public view returns (uint256) {
        IAToken aToken = IAToken(IStrategyInterface(_strategy).aToken());
        IRewardsController rewardsController = IRewardsController(
            aToken.getIncentivesController()
        );

        address[] memory rewardTokens = rewardsController.getRewardsByAsset(
            address(aToken)
        );
        uint256 i;
        uint256 tokenIncentivesRate;
        //Passes the total Supply and the corresponding reward token address for each reward token the want has
        for (i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            if (rewardToken == address(0)) return 0;

            // make sure we should be calculating the apr and that the distro period hasn't ended
            if (
                block.timestamp <
                rewardsController.getDistributionEnd(
                    address(aToken),
                    rewardToken
                )
            ) {
                uint256 _emissionsPerSecond;
                (, _emissionsPerSecond, , ) = rewardsController.getRewardsData(
                    address(aToken),
                    rewardToken
                );
                if (_emissionsPerSecond > 0) {
                    uint256 emissionsInAsset;
                    // we need to get the market rate from the reward token to want
                    if (
                        rewardToken == _asset || rewardToken == address(aToken)
                    ) {
                        // no calculation needed if rewarded in want
                        emissionsInAsset = _emissionsPerSecond;
                    } else if (rewardToken == address(stkAave)) {
                        // if the reward token is stkAave we will be selling Aave
                        emissionsInAsset = _checkPrice(
                            AAVE,
                            _asset,
                            _emissionsPerSecond
                        );
                    } else {
                        // else just check the price
                        emissionsInAsset = _checkPrice(
                            rewardToken,
                            _asset,
                            _emissionsPerSecond
                        ); // amount of emissions in want
                    }

                    tokenIncentivesRate +=
                        (emissionsInAsset * SECONDS_IN_YEAR * 1e18) /
                        _underlyingBalance; // APRs are in 1e18
                }
            }
        }
        return (tokenIncentivesRate * 9_500) / 10_000; // 95% of estimated APR to avoid overestimations
    }

    function _checkPrice(
        address start,
        address end,
        uint256 _amount
    ) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        try router.getAmountsOut(_amount, getTokenOutPath(start, end)) returns (
            uint256[] memory amounts
        ) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }

    function getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal view returns (address[] memory _path) {
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
