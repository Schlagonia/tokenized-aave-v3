// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {AaveV3LenderFactory} from "../src/AaveV3LenderFactory.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    // Create X address.
    Deployer public deployer =
        Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public weth = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address public v2_router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    function run() external {
        vm.startBroadcast();

        
        AaveV3LenderFactory factory = new AaveV3LenderFactory(
            0xB0612167D2C749131a07c07c254119b9E613c287,
            0xB0612167D2C749131a07c07c254119b9E613c287,
            0x52605BbF54845f520a3E94792d019f62407db2f8, 
            0x35442eC4C1A0C4E864c2Bc45bfc5d17fCEE8ac4C,
            0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3,
            0x1D368773735ee1E678950B7A97bcA2CafB330CDc,
            weth
        );

        console.log("Factory deployed at", address(factory));
        

        StrategyAprOracle oracle = new StrategyAprOracle(
            weth,
            v2_router
        );

        console.log("Oracle deployed at", address(oracle));

        address sLender = factory.newAaveV3Lender(address(weth));  

        IStrategyInterface(sLender).acceptManagement();
        console.log("S Lender deployed at", address(sLender));

        address usdcLender = factory.newAaveV3Lender(address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894));

        IStrategyInterface(usdcLender).acceptManagement();
        console.log("USDC Lender deployed at", address(usdcLender));

        address wethLender = factory.newAaveV3Lender(address(0x50c42dEAcD8Fc9773493ED674b675bE577f2634b));

        IStrategyInterface(wethLender).acceptManagement();
        console.log("WETH Lender deployed at", address(wethLender));

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
