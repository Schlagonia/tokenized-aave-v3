// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {AaveV3LenderFactory} from "../src/AaveV3LenderFactory.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    // Create X address.
    Deployer public deployer =
        Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public initGov = 0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8;

    function run() external {
        vm.startBroadcast();

        AaveV3LenderFactory factory = new AaveV3LenderFactory(
            0x2D57bB1Ad5EaB2caacb50e8527eb0eE504f49e48,
            0x2D57bB1Ad5EaB2caacb50e8527eb0eE504f49e48,
            0x52605BbF54845f520a3E94792d019f62407db2f8,
            0x01fE3347316b2223961B20689C65eaeA71348e93,
            0xA238Dd80C259a72e81d7e4664a9801593F98d1c5,
            0x2626664c2603336E57B271c5C0b26F421741e481,
            0x4200000000000000000000000000000000000006
        );

        console.log("Factory deployed at", address(factory));

        StrategyAprOracle oracle = new StrategyAprOracle();
        console.log("Oracle deployed at", address(oracle));

        address usdcLender = factory.newAaveV3Lender(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        );
        console.log("USDC Lender deployed at", usdcLender);

        address wethLender = factory.newAaveV3Lender(
            0x4200000000000000000000000000000000000006
        );
        console.log("WETH Lender deployed at", wethLender);

        address cbbtcLender = factory.newAaveV3Lender(
            0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
        );
        console.log("CB-BTC Lender deployed at", cbbtcLender);

        address cbethLender = factory.newAaveV3Lender(
            0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
        );
        console.log("CBETH Lender deployed at", cbethLender);

        vm.stopBroadcast();
    }
}

contract Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) public payable returns (address newContract) {}
}
