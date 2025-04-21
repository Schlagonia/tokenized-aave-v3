// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ExtendedTest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "../../../src/interfaces/IStrategyInterface.sol";
import {AaveV3LenderFactory} from "../../../src/AaveV3LenderFactory.sol";
import {StrategyAprOracle} from "../../../src/periphery/StrategyAprOracle.sol";

contract Setup is ExtendedTest {
    // Tokens
    ERC20 public constant DAI =
        ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant WETH =
        ERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    ERC20 public constant USDC =
        ERC20(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    ERC20 public constant AAVE =
        ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    ERC20 public asset;

    uint256 public constant RELATIVE_APPROX = 1e5;

    // Contracts
    IStrategyInterface public strategy;
    AaveV3LenderFactory public factory;
    //StrategyAprOracle public oracle;

    uint256 public MAX_BPS = 10_000;
    // Addresses
    address public constant LENDING_POOL =
        0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3;
    address public constant ROUTER = 0x1D368773735ee1E678950B7A97bcA2CafB330CDc;
    address public constant WHALE = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address public daddy;
    address public user;
    address public rewards;
    address public management;
    address public keeper;
    address public buyer;

    uint256 public minFuzzAmount;
    uint256 public maxFuzzAmount;
    uint256 public wethAmount;

    function setUp() public virtual {
        // Setup accounts
        daddy = makeAddr("daddy");
        user = makeAddr("user");
        rewards = makeAddr("rewards");
        management = makeAddr("management");
        keeper = makeAddr("keeper");
        buyer = makeAddr("buyer");

        asset = WETH;

        // Setup amounts
        minFuzzAmount = 100_000;
        maxFuzzAmount = 100_000 * 10 ** asset.decimals();
        wethAmount = 10 ** WETH.decimals();

        // Deploy factory
        factory = new AaveV3LenderFactory(
            management,
            rewards,
            keeper,
            daddy,
            LENDING_POOL,
            ROUTER,
            address(WETH)
        );

        // Deploy strategy
        strategy = IStrategyInterface(factory.newAaveV3Lender(address(asset)));
        vm.prank(management);
        strategy.acceptManagement();
        vm.prank(management);
        strategy.setPerformanceFee(1000); // 10% performance fee

        // Deploy oracle
        //oracle = new StrategyAprOracle();
    }

    function createStrategy(
        address _asset,
        uint256 _performanceFee
    ) public returns (IStrategyInterface) {
        IStrategyInterface newStrategy = IStrategyInterface(
            factory.newAaveV3Lender(_asset)
        );
        vm.prank(management);
        newStrategy.acceptManagement();
        vm.prank(management);
        newStrategy.setPerformanceFee(uint16(_performanceFee));
        return newStrategy;
    }

    function deposit(
        IStrategyInterface _strategy,
        ERC20 _asset,
        uint256 _amount,
        address _account
    ) public {
        vm.startPrank(_account);
        _asset.approve(address(_strategy), _amount);
        _strategy.deposit(_amount, _account);
        vm.stopPrank();
    }
}
