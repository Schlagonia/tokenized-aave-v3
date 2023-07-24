// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy, IUniswapV3Swapper {
    function claimRewards() external view returns (bool);

    function minAmountToSellMapping(
        address _token
    ) external view returns (uint256);

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function sellRewardManually(address _token, uint256 _minAmountOut) external;

    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external;

    function setClaimRewards(bool _bool) external;
}
