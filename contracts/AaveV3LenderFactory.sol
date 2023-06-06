// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AaveV3Lender} from "./AaveV3Lender.sol";

interface IStrategy {
    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setManagement(address) external;
}

contract AaveV3LenderFactory {
    event NewAaveV3Lender(address indexed strategy, address indexed asset);

    constructor(address _asset, string memory _name) {
        newAaveV3Lender(_asset, _name, msg.sender, msg.sender, msg.sender);
    }

    function newAaveV3Lender(
        address _asset,
        string memory _name
    ) public returns (address) {
        return
            newAaveV3Lender(_asset, _name, msg.sender, msg.sender, msg.sender);
    }

    function newAaveV3Lender(
        address _asset,
        string memory _name,
        address _performanceFeeRecipient,
        address _keeper,
        address _management
    ) public returns (address) {
        IStrategy newStrategy = IStrategy(
            address(new AaveV3Lender(_asset, _name))
        );

        newStrategy.setPerformanceFeeRecipient(_performanceFeeRecipient);

        newStrategy.setKeeper(_keeper);

        newStrategy.setManagement(_management);

        emit NewAaveV3Lender(address(newStrategy), _asset);
        return address(newStrategy);
    }
}
