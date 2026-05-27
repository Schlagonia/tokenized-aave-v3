// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {SparkLender, ERC20} from "./SparkLender.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract SparkLenderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewSparkLender(address indexed strategy, address indexed asset);

    address public immutable SMS;

    address public immutable LENDING_POOL;
    address public immutable ROUTER;
    address public immutable BASE;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _sms,
        address _lendingPool,
        address _router,
        address _base
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        SMS = _sms;
        LENDING_POOL = _lendingPool;
        ROUTER = _router;
        BASE = _base;
    }

    /**
     * @notice Deploy a new Spark Lender.
     * @param _asset The underlying asset for the lender to use.
     * @return . The address of the new lender.
     */
    function newSparkLender(address _asset) external returns (address) {
        if (deployments[_asset] != address(0)) {
            revert AlreadyDeployed(deployments[_asset]);
        }

        string memory _name = string(abi.encodePacked("Spark ", ERC20(_asset).symbol(), " Lender"));

        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy =
            IStrategyInterface(address(new SparkLender(_asset, _name, LENDING_POOL, ROUTER, BASE)));

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(SMS);

        newStrategy.setPerformanceFee(0);

        newStrategy.setProfitMaxUnlockTime(0);

        emit NewSparkLender(address(newStrategy), _asset);

        deployments[_asset] = address(newStrategy);
        return address(newStrategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
