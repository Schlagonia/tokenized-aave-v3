// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

import {IPool, DataTypesV3} from "../interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "../interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IReserveInterestRateStrategy} from "../interfaces/Aave/V3/IReserveInterestRateStrategy.sol";

contract StrategyAprOracle {
    IPool public constant lendingPool =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    IProtocolDataProvider public constant protocolDataProvider =
        IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);

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
        //need to calculate new supplyRate after Deposit (when deposit has not been done yet)
        DataTypesV3.ReserveData memory reserveData = lendingPool
            .getReserveDataExtended(asset);

        (
            uint256 unbacked,
            ,
            ,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            ,
            ,
            ,
            uint256 averageStableBorrowRate,
            ,
            ,

        ) = protocolDataProvider.getReserveData(asset);

        (, , , , uint256 reserveFactor, , , , , ) = protocolDataProvider
            .getReserveConfigurationData(asset);

        DataTypesV3.CalculateInterestRatesParams memory params = DataTypesV3
            .CalculateInterestRatesParams(
                unbacked,
                _delta > 0 ? uint256(_delta) : 0,
                _delta < 0 ? uint256(-1 * _delta) : 0,
                totalStableDebt,
                totalVariableDebt,
                averageStableBorrowRate,
                reserveFactor,
                asset,
                true,
                uint256(reserveData.virtualUnderlyingBalance)
            );

        (uint256 newLiquidityRate, , ) = IReserveInterestRateStrategy(
            reserveData.interestRateStrategyAddress
        ).calculateInterestRates(params);

        return newLiquidityRate / 1e9; // divided by 1e9 to go from Ray to Wad
    }
}
