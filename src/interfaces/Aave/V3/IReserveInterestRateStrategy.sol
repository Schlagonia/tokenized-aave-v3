// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import {DataTypesV3} from "./DataTypesV3.sol";

/**
 * @title IReserveInterestRateStrategy
 * @author Aave
 * @notice Interface for the calculation of the interest rates
 */
interface IReserveInterestRateStrategy {
    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations
     * @param params The parameters needed to calculate interest rates
     * @return liquidityRate The liquidity rate expressed in ray
     * @return variableBorrowRate The variable borrow rate expressed in ray
     */
    function calculateInterestRates(
        DataTypesV3.CalculateInterestRatesParams memory params
    ) external view returns (uint256, uint256);
}
