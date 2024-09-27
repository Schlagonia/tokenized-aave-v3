// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/Setup.sol";
import {IStrategyInterface} from "../../src/interfaces/IStrategyInterface.sol";

contract TestAccess is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testManagementAccess() public {
        // Test setPerformanceFee
        vm.prank(management);
        strategy.setPerformanceFee(1_500); // 15%
        assertEq(strategy.performanceFee(), 1_500);

        // Test setProfitMaxUnlockTime
        vm.prank(management);
        strategy.setProfitMaxUnlockTime(3 days);
        assertEq(strategy.profitMaxUnlockTime(), 3 days);

        // Test setKeeper
        address newKeeper = makeAddr("newKeeper");
        vm.prank(management);
        strategy.setKeeper(newKeeper);
        assertEq(strategy.keeper(), newKeeper);

        // Test acceptManagement
        address newManagement = makeAddr("newManagement");
        vm.prank(management);
        strategy.setPendingManagement(newManagement);
        assertEq(strategy.management(), management); // Still old management
        assertEq(strategy.pendingManagement(), newManagement);

        vm.prank(newManagement);
        strategy.acceptManagement();
        assertEq(strategy.management(), newManagement);
        assertEq(strategy.pendingManagement(), address(0));
    }

    function testOnlyManagementCanSetPerformanceFee() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setPerformanceFee(1_500);
    }

    function testOnlyManagementCanSetProfitMaxUnlockTime() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setProfitMaxUnlockTime(3 days);
    }

    function testOnlyManagementCanSetKeeper() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setKeeper(address(0));
    }

    function testOnlyManagementCansetPendingManagement() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setPendingManagement(address(0));
    }

    function testOnlyPendingManagementCanAcceptManagement() public {
        address newManagement = makeAddr("newManagement");
        vm.prank(management);
        strategy.setPendingManagement(newManagement);

        vm.prank(user);
        vm.expectRevert("!pending");
        strategy.acceptManagement();
    }

    function testKeeperAccess() public {
        // Test tend
        vm.prank(keeper);
        strategy.tend();

        // Test report
        vm.prank(keeper);
        strategy.report();
    }

    function testOnlyKeeperCanTend() public {
        vm.prank(user);
        vm.expectRevert("!keeper");
        strategy.tend();
    }

    function testOnlyKeeperCanReport() public {
        vm.prank(user);
        vm.expectRevert("!keeper");
        strategy.report();
    }
}
