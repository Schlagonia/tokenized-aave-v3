// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";
import {IAuctionSwapper} from "@periphery/swappers/interfaces/IAuctionSwapper.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IBaseHealthCheck, IUniswapV3Swapper, IAuctionSwapper {
    function LENDING_POOL() external view returns (address);

    function A_TOKEN() external view returns (address);

    function claimRewards() external view returns (bool);

    function REWARDS_CONTROLLER() external view returns (address);

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setMinAmountToSell(address _token, uint256 _amount) external;

    function setClaimRewards(bool _bool) external;

    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;
}
