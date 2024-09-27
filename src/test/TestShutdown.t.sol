// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestShutdown is Setup {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_emergency_withdraw(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit to the strategy
        deal(address(asset), user, _amount);
        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(10000);

        assertEq(asset.balanceOf(address(strategy)), 0);

        // Need to shutdown the strategy, and withdraw
        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management);
        strategy.emergencyWithdraw(_amount);

        assertGe(asset.balanceOf(address(strategy)), _amount);

        assertEq(strategy.totalAssets(), _amount);

        skip(strategy.profitMaxUnlockTime() - 1);

        // withdrawal
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0);

        assertApproxEqRel(
            asset.balanceOf(user),
            userBalanceBefore,
            RELATIVE_APPROX
        );
    }

    function test_shutdown_report_doesnt_reinvest(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit to the strategy
        deal(address(asset), user, _amount);
        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        uint256 toWithdraw = _amount / 2;

        vm.prank(management);
        strategy.emergencyWithdraw(toWithdraw);

        assertEq(asset.balanceOf(address(strategy)), toWithdraw);

        // Report should still work correctly
        vm.prank(management);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0);
        assertEq(loss, 0);

        uint256 performanceFees = (profit * strategy.performanceFee()) /
            MAX_BPS;

        assertEq(strategy.totalAssets(), _amount + profit);

        // needed for profits to unlock
        skip(strategy.profitMaxUnlockTime() - 1);

        // withdrawal
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(asset.balanceOf(user), userBalanceBefore);
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        deal(address(asset), user, _amount);
        // Deposit into strategy
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}
