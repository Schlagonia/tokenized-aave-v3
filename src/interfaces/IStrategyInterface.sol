// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IAuctionSwapper} from "@periphery/swappers/interfaces/IAuctionSwapper.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy, IUniswapV3Swapper, IAuctionSwapper {
    function lendingPool() external view returns (address);

    function aToken() external view returns (address);

    function manualRedeemAave() external;

    function claimRewards() external view returns (bool);

    function useAuction() external view returns (bool);

    function rewardsController() external view returns (address);

    function minAmountToSellMapping(
        address _token
    ) external view returns (uint256);

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external;

    function setClaimRewards(bool _bool) external;

    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;

    function kickAuction(address _token) external returns (uint256);
}
