// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./utils/Setup.sol";
import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";

contract TestOracle is Setup {
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

        uint256 newApr = oracle.aprAfterDebtChange(
            _strategy,
            10000000000000000000
        );

        assertLt(newApr, currentApr);

        uint256 higherApr = oracle.aprAfterDebtChange(
            _strategy,
            -10000000000000000
        );

        assertGt(higherApr, currentApr);

        // This is equivalent to the print statement in Python
        emit log_named_uint(
            "Current apr",
            oracle.aprAfterDebtChange(_strategy, 0)
        );
    }

    function test_oracle() public {
        address oracle = address(new StrategyAprOracle());

        check_oracle(oracle, address(strategy), user, management);
    }
}
