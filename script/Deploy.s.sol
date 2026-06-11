// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {SparkLenderFactory} from "../src/SparkLenderFactory.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    address public management = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address public performanceFeeRecipient = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address public keeper = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address public sam = 0xe5e2Baf96198c56380dDD5E992D7d1ADa0e989c0;
    address public lendingPool = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run() external {
        vm.startBroadcast();

        SparkLenderFactory factory =
            new SparkLenderFactory(management, performanceFeeRecipient, keeper, sam, lendingPool, router, base);

        console.log("Factory deployed at", address(factory));

        StrategyAprOracle oracle = new StrategyAprOracle(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        //console.log("Oracle deployed at", address(oracle));

        address usdcLender = factory.newSparkLender(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        console.log("USDC Lender deployed at", usdcLender);

        address wethLender = factory.newSparkLender(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        console.log("WETH Lender deployed at", wethLender);

        address usdtLender = factory.newSparkLender(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        console.log("USDT Lender deployed at", usdtLender);

        vm.stopBroadcast();
    }
}

