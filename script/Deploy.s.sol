// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {SparkLenderFactory} from "../src/SparkLenderFactory.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    // Create X address.
    Deployer public deployer = Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public initGov = 0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8;

    function run() external {
        vm.startBroadcast();

        SparkLenderFactory factory = new SparkLenderFactory(
            0x2D57bB1Ad5EaB2caacb50e8527eb0eE504f49e48,
            0x2D57bB1Ad5EaB2caacb50e8527eb0eE504f49e48,
            0x52605BbF54845f520a3E94792d019f62407db2f8,
            0x01fE3347316b2223961B20689C65eaeA71348e93,
            0xC13e21B648A5Ee794902342038FF3aDAB66BE987,
            0xE592427A0AEce92De3Edee1F18E0157C05861564,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        console.log("Factory deployed at", address(factory));

        StrategyAprOracle oracle = new StrategyAprOracle(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        console.log("Oracle deployed at", address(oracle));

        address usdcLender = factory.newSparkLender(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        console.log("USDC Lender deployed at", usdcLender);

        address daiLender = factory.newSparkLender(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        console.log("DAI Lender deployed at", daiLender);

        address wethLender = factory.newSparkLender(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        console.log("WETH Lender deployed at", wethLender);

        vm.stopBroadcast();
    }
}

contract Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate2(bytes32 salt, bytes memory initCode) public payable returns (address newContract) {}
}
