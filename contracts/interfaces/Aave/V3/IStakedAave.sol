// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.12;

interface IStakedAave {
    struct CooldownSnapshot {
        uint40 timestamp;
        uint216 amount;
    }

    function stake(address to, uint256 amount) external;

    function redeem(address to, uint256 amount) external;

    function cooldown() external;

    function claimRewards(address to, uint256 amount) external;

    function getTotalRewardsBalance(address) external view returns (uint256);

    function getCooldownSeconds() external view returns (uint256);

    function stakersCooldowns(
        address
    ) external view returns (CooldownSnapshot memory);

    function UNSTAKE_WINDOW() external view returns (uint256);
}
