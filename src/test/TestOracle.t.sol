// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategyInterface} from "./utils/Setup.sol";
import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";

contract TestOracle is Setup {
    address public v2_router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function setUp() public override {
        super.setUp();
    }

    function check_oracle(
        address _oracle,
        address _strategy,
        address _user,
        address _management
    ) internal {
        StrategyAprOracle oracle = StrategyAprOracle(_oracle);

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        assertGt(currentApr, 0);
        // If APR is expected to be under 100%
        assertLt(currentApr, 1e18);

        uint256 newApr = oracle.aprAfterDebtChange(_strategy, 1_000e6);

        assertLt(newApr, currentApr);

        uint256 higherApr = oracle.aprAfterDebtChange(_strategy, -1_000e6);

        assertGt(higherApr, currentApr);
    }

    function test_oracle() public {
        address oracle = address(
            new StrategyAprOracle(address(WETH), address(v2_router))
        );

        vm.prank(strategy.management());
        strategy.setClaimRewards(true);

        check_oracle(oracle, address(strategy), user, management);
    }
}
