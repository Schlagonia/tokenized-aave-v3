// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AaveV3Lender} from "./AaveV3Lender.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract AaveV3LenderFactory {
    event NewAaveV3Lender(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    /**
     * @notice Deploy a new Aave V3 Lender.
     * @dev This will set the msg.sender to all of the permissioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newAaveV3Lender(
        address _asset,
        string memory _name
    ) external returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new AaveV3Lender(_asset, _name))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewAaveV3Lender(address(newStrategy), _asset);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }
}
