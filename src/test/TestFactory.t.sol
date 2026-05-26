// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./utils/Setup.sol";
//import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {AuctionFactory} from "@periphery/Auctions/AuctionFactory.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestFactory is Setup {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_factory_deployed_operation(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        address _asset = address(asset) == address(WETH) ? address(USDC) : address(WETH);
        if (_asset == address(USDC)) {
            _amount = 100_000 * 1e6;
        }

        vm.prank(management);
        address newStrategy = factory.newSparkLender(_asset);

        IStrategyInterface strategy = IStrategyInterface(newStrategy);

        vm.prank(management);
        strategy.acceptManagement();

        deal(_asset, user, _amount);

        uint256 userBalanceBefore = ERC20(_asset).balanceOf(user);

        vm.startPrank(user);
        ERC20(_asset).approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(1 days);

        vm.prank(user);
        strategy.withdraw(_amount, user, user);

        assertEq(strategy.totalAssets(), 0);
        assertApproxEqRel(ERC20(_asset).balanceOf(user), userBalanceBefore, RELATIVE_APPROX);
    }

    function test_factory_deployed_profitable_report(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        address _asset = address(asset) == address(WETH) ? address(USDC) : address(WETH);
        uint16 aaveFee = 3000;
        if (_asset == address(USDC)) {
            _amount = 100_000 * 1e6;
        }

        vm.prank(management);
        address newStrategy = factory.newSparkLender(_asset);

        IStrategyInterface strategy = IStrategyInterface(newStrategy);

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        strategy.setUniFees(address(AAVE), _asset, aaveFee);

        deal(_asset, user, _amount);

        uint256 userBalanceBefore = ERC20(_asset).balanceOf(user);

        vm.startPrank(user);
        ERC20(_asset).approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(5 days);

        uint256 beforePps = strategy.pricePerShare();

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0);
        assertEq(loss, 0);

        assertGe(strategy.totalAssets(), _amount + profit);

        skip(strategy.profitMaxUnlockTime() - 1);

        assertGe(strategy.totalAssets(), _amount);
        assertGt(strategy.pricePerShare(), beforePps);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(ERC20(_asset).balanceOf(user), userBalanceBefore);
    }

    function test_factory_deployed_reward_selling_auction(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        address _asset = address(asset) == address(WETH) ? address(USDC) : address(WETH);
        if (_asset == address(USDC)) {
            _amount = 100_000 * 1e6;
        }

        vm.prank(management);
        address newStrategy = factory.newSparkLender(_asset);

        IStrategyInterface strategy = IStrategyInterface(newStrategy);

        vm.prank(management);
        strategy.acceptManagement();

        deal(_asset, user, _amount);

        assertFalse(strategy.useAuction());

        AuctionFactory auctionFactory = new AuctionFactory();

        vm.prank(management);
        address newAuction = auctionFactory.createNewAuction(_asset, address(strategy), management);

        Auction auction = Auction(newAuction);

        vm.prank(management);
        strategy.setAuction(address(auction));
        assertTrue(strategy.useAuction());

        vm.prank(management);
        auction.enable(address(AAVE));

        vm.startPrank(user);
        ERC20(_asset).approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(5 days);

        uint256 aaveAmount = 1e18;
        deal(address(AAVE), address(strategy), aaveAmount);
        assertEq(AAVE.balanceOf(address(strategy)), aaveAmount);

        assertEq(strategy.kickable(address(AAVE)), aaveAmount);

        vm.prank(management);
        assertEq(strategy.kickAuction(address(AAVE)), aaveAmount);
        assertEq(AAVE.balanceOf(address(auction)), aaveAmount);

        skip(auction.auctionLength() / 2);

        uint256 needed = auction.getAmountNeeded(address(AAVE), aaveAmount);

        assertGt(needed, 0);

        deal(_asset, buyer, needed);

        vm.startPrank(buyer);
        ERC20(_asset).approve(address(auction), needed);
        auction.take(address(AAVE));
        vm.stopPrank();

        assertEq(AAVE.balanceOf(address(auction)), 0);
        assertEq(AAVE.balanceOf(address(strategy)), 0);
        assertEq(ERC20(_asset).balanceOf(address(strategy)), needed);

        uint256 beforePps = strategy.pricePerShare();

        vm.prank(keeper);
        (uint256 profit,) = strategy.report();

        assertGt(profit, 0);
        assertEq(strategy.totalAssets(), _amount + profit);

        assertEq(AAVE.balanceOf(address(strategy)), 0);
        assertGt(ERC20(_asset).balanceOf(address(strategy)), 0);

        skip(strategy.profitMaxUnlockTime() - 1);

        assertEq(strategy.totalAssets(), _amount + profit);
        assertGt(strategy.pricePerShare(), beforePps);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGt(ERC20(_asset).balanceOf(user), _amount);
    }

    function test_factory_deployed_shutdown(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        address _asset = address(asset) == address(WETH) ? address(USDC) : address(WETH);
        if (_asset == address(USDC)) {
            _amount = 100_000 * 1e6;
        }

        vm.prank(management);
        address newStrategy = factory.newSparkLender(_asset);

        IStrategyInterface strategy = IStrategyInterface(newStrategy);

        vm.prank(management);
        strategy.acceptManagement();

        deal(_asset, user, _amount);

        uint256 userBalanceBefore = ERC20(_asset).balanceOf(user);

        vm.startPrank(user);
        ERC20(_asset).approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);

        skip(14);

        assertEq(ERC20(_asset).balanceOf(address(strategy)), 0);

        vm.startPrank(management);
        strategy.shutdownStrategy();
        strategy.emergencyWithdraw(_amount);
        strategy.report();
        vm.stopPrank();

        assertGe(ERC20(_asset).balanceOf(address(strategy)), _amount);
        assertGe(strategy.totalAssets(), _amount);

        vm.prank(user);
        strategy.withdraw(_amount, user, user);

        assertApproxEqRel(ERC20(_asset).balanceOf(user), userBalanceBefore, RELATIVE_APPROX);
    }

    function test_factory_deployed_access(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        address _asset = address(asset) == address(WETH) ? address(USDC) : address(WETH);
        if (_asset == address(USDC)) {
            _amount = 100_000 * 1e6;
        }

        vm.prank(management);
        address newStrategy = factory.newSparkLender(_asset);

        IStrategyInterface strategy = IStrategyInterface(newStrategy);

        vm.prank(management);
        strategy.acceptManagement();

        deal(_asset, user, _amount);

        assertEq(strategy.uniFees(address(AAVE), address(WETH)), 0);
        assertEq(strategy.uniFees(address(WETH), address(AAVE)), 0);

        vm.prank(management);
        strategy.setUniFees(address(AAVE), address(WETH), 300);

        assertEq(strategy.uniFees(address(AAVE), address(WETH)), 300);
        assertEq(strategy.uniFees(address(WETH), address(AAVE)), 300);

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setUniFees(address(WETH), address(AAVE), 0);

        assertEq(strategy.uniFees(address(AAVE), address(WETH)), 300);
        assertEq(strategy.uniFees(address(WETH), address(AAVE)), 300);

        vm.prank(user);
        vm.expectRevert("!emergency authorized");
        strategy.emergencyWithdraw(100);
    }
}
