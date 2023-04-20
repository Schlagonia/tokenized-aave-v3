// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "./interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract AaveV3Lender is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    // The pool to deposit and withdraw through.
    IPool public constant lendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    // The a Token specific rewards contract for claiming rewards.
    IRewardsController public rewardsController;

    // The token that we get in return for deposits.
    IAToken public aToken;

    // Mapping to be set by management for any reward tokens
    // that should not or can not be sold. This can be used
    // if selling a reward token is reverting to allow for
    // reports to still work properly.
    mapping(address => bool) public dontSell;

    constructor(
        address _asset,
        string memory _name
    ) BaseTokenizedStrategy(_asset, _name) {
        initializeAaveV3Lender(_asset);
    }

    function initializeAaveV3Lender(address _asset) public {
        // Make sure we are not already initialized.
        require(address(aToken) == address(0), "already initialized");

        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Make sure its a real token.
        require(address(aToken) != address(0), "!aToken");

        // Set the rewards controller
        rewardsController = aToken.getIncentivesController();

        // Make approve the lending pool for cheaper deposits.
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);

        // Set uni swapper values
        minAmountToSell = 1e4;
        base = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    }

    /**
     * @notice Set the uni fees for swaps.
     * @dev External function available to management to set
     * the fees used in the `UniswapV3Swapper.
     *
     * Any incentived tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /**
     * @notice Set the min amount to sell.
     * @dev External function available to management to set
     * the `minAmountToSell` variable in the `UniswapV3Swapper`.
     *
     * @param _minAmountToSell The min amount of tokens to sell.
     */
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should invest up to '_amount' of 'asset'.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _invest(uint256 _amount) internal override {
        lendingPool.supply(asset, _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * Should do any needed parameter checks, '_amount' may be more
     * than is actually available.
     *
     * This function is called {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // We dont check available liquidity because we need the tx to
        // revert if there is not enough liquidity so we dont improperly
        // pass a loss on to the user withdrawing.
        lendingPool.withdraw(
            asset,
            Math.min(aToken.balanceOf(address(this)), _amount),
            address(this)
        );
    }

    /**
     * @dev Internal non-view function to harvest all rewards, reinvest
     * and return the accurate amount of funds currently held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * reinvesting etc. to get the most accurate view of current assets.
     *
     * All applicable assets including loose assets should be accounted
     * for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * @return _invested A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds.
     */
    function _totalInvested() internal override returns (uint256 _invested) {
        if (!TokenizedStrategy.isShutdown()) {
            // Claim and sell any rewards to `asset`.
            _claimAndSellRewards();

            // deposit any loose funds
            uint256 looseAsset = ERC20(asset).balanceOf(address(this));
            if (looseAsset > 0) {
                lendingPool.supply(asset, looseAsset, address(this), 0);
            }
        }

        _invested =
            aToken.balanceOf(address(this)) +
            ERC20(asset).balanceOf(address(this));
    }

    // Claim all pending reward and sell if applicable.
    function _claimAndSellRewards() internal {
        //claim all rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);

        //swap as much as possible back to want
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == asset || dontSell[token]) {
                continue;
            } else {
                _swapFrom(
                    token,
                    asset,
                    ERC20(token).balanceOf(address(this)),
                    0
                );
            }
        }
    }

    /**
     * @notice Set the `dontSell` mapping for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _calimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _sell Bool to set the mapping to for `_token`.
     */
    function setDontSell(address _token, bool _sell) external onlyManagement {
        dontSell[_token] = _sell;
    }

    /**
     * @notice Manually withdraw an `_amount` from Aave.
     * @dev To be used by management in the case of an emergency with
     * either the strategy or Aave to manually pull funds out at whichever
     * rate works.
     *
     * This should be combined with shutting down the strategy as well as
     * a `report`.
     *
     * NOTE: If a report is not called after this all withdraws will fail.
     *
     * @param _amount The amount of `asset` to withdraw from Aave.
     */
    function emergencyWithdraw(uint256 _amount) external onlyManagement {
        lendingPool.withdraw(asset, _amount, address(this));
    }

    // Clone the lender for a new asset.
    function cloneAaveV3Lender(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newLender) {
        // Use the cloning logic held withen the Tokenized Strategy.
        newLender = TokenizedStrategy.clone(
            _asset,
            _name,
            _management,
            _performanceFeeRecipient,
            _keeper
        );

        // Neeed to cast address to payable since there is a fallback function.
        AaveV3Lender(payable(newLender)).initializeAaveV3Lender(_asset);
    }
}
