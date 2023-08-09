// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AaveV3Lender} from "./AaveV3Lender.sol";

interface IStrategy {
    function setPerformanceFeeRecipient(address) external;

    function setKeeper(address) external;

    function setPendingManagement(address) external;
}

contract AaveV3LenderFactory {
    event NewAaveV3Lender(address indexed strategy, address indexed asset);

    address public management;
    address public perfomanceFeeRecipient;
    address public keeper;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        perfomanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
    }

    /**
     * @notice Deploye a new Aave V3 Lender.
     * @dev This will set the msg.sender to all of the permisioned roles.
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
        IStrategy newStrategy = IStrategy(
            address(new AaveV3Lender(_asset, _name))
        );

        newStrategy.setPerformanceFeeRecipient(perfomanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewAaveV3Lender(address(newStrategy), _asset);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _perfomanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        perfomanceFeeRecipient = _perfomanceFeeRecipient;
        keeper = _keeper;
    }
}
