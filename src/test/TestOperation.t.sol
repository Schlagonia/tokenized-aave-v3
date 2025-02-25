// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./utils/Setup.sol";
import {IPool} from "../../src/interfaces/Aave/V3/IPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestOperation is Setup {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_operation(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit to the strategy
        deal(address(asset), user, _amount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(1000);

        // withdrawal
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0);
        assertEq(asset.balanceOf(user), userBalanceBefore);
    }

    function test_profitable_report(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        // Deposit to the strategy
        deal(address(asset), user, _amount);
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(2 days);

        uint256 beforePps = strategy.pricePerShare();

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGe(profit, 0);
        assertEq(loss, 0);

        assertEq(strategy.totalAssets(), _amount + profit);

        // needed for profits to unlock
        skip(strategy.profitMaxUnlockTime() - 1);

        assertEq(strategy.totalAssets(), _amount + profit);
        assertGt(strategy.pricePerShare(), beforePps);

        // withdrawal
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(asset.balanceOf(user), userBalanceBefore);
    }

    function test_profitable_report_with_fee(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Set performance fee to 10%
        uint256 performanceFee = 1_000;
        vm.prank(management);
        strategy.setPerformanceFee(uint16(performanceFee));

        // Deposit to the strategy
        deal(address(asset), user, _amount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(2 days);

        uint256 beforePps = strategy.pricePerShare();

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0);
        assertEq(loss, 0);

        assertEq(strategy.totalAssets(), _amount + profit);

        // needed for profits to unlock
        skip(strategy.profitMaxUnlockTime());

        assertEq(strategy.totalAssets(), _amount + profit);
        assertGt(strategy.pricePerShare(), beforePps);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(asset.balanceOf(user), userBalanceBefore);

        uint256 rewardsBalance = strategy.balanceOf(rewards);

        if (rewardsBalance > 0) {
            vm.prank(rewards);
            strategy.redeem(rewardsBalance, rewards, rewards);
        }
    }

    function test_withdraw_limit_airdrop(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit to the strategy
        deal(address(asset), user, _amount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        address aToken = strategy.aToken();

        uint256 limit = strategy.availableWithdrawLimit(user);

        assertLe(limit, asset.balanceOf(aToken));
        assertGt(limit, _amount);

        deal(address(asset), WHALE, _amount);
        vm.prank(WHALE);
        asset.transfer(aToken, _amount);

        uint256 newLimit = strategy.availableWithdrawLimit(user);

        // Should not be affected
        assertEq(newLimit, limit);
        assertLt(limit, asset.balanceOf(aToken));
        assertGt(limit, _amount);

        skip(1000);

        // withdrawal
        vm.prank(user);
        strategy.withdraw(_amount, user, user);

        assertEq(strategy.totalAssets(), 0);
        assertEq(asset.balanceOf(user), userBalanceBefore);
    }

    function test_withdraw_limit_illiquid(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit to the strategy
        deal(address(asset), user, _amount);
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        uint256 toLeave = _amount / 10;

        vm.mockCall(
            address(LENDING_POOL),
            abi.encodeWithSelector(
                IPool.getVirtualUnderlyingBalance.selector,
                address(asset)
            ),
            abi.encode(toLeave)
        );

        assertEq(strategy.availableWithdrawLimit(user), toLeave);
        assertEq(strategy.maxWithdraw(user), toLeave);

        uint256 maxRedeem = strategy.maxRedeem(user);

        vm.prank(user);
        strategy.redeem(maxRedeem, user, user);

        vm.mockCall(
            address(LENDING_POOL),
            abi.encodeWithSelector(
                IPool.getVirtualUnderlyingBalance.selector,
                address(asset)
            ),
            abi.encode(0)
        );

        assertEq(strategy.maxRedeem(user), 0);

        vm.expectRevert("ERC4626: redeem more than max");
        vm.prank(user);
        strategy.redeem(1, user, user);
    }

    function test_tend_trigger(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);

        // Deposit to the strategy
        deal(address(asset), user, _amount);
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        (trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);

        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);

        // needed for profits to unlock
        skip(strategy.profitMaxUnlockTime() - 1);

        (trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertFalse(trigger);
    }
}
