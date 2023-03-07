// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {IEvents} from "./IEvents.sol";
import {IExchanger} from "@synthetix/IExchanger.sol";
import {IFactory} from "./IFactory.sol";
import {IFuturesMarketManager} from "@synthetix/IFuturesMarketManager.sol";
import {IPerpsV2MarketConsolidated} from "@synthetix/IPerpsV2MarketConsolidated.sol";
import {ISettings} from "./ISettings.sol";

/// @title Kwenta Smart Margin Account Implementation Interface
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IAccount {
    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    /// @notice Command Flags used to decode commands to execute
    /// @dev under the hood PERPS_V2_MODIFY_MARGIN = 0, PERPS_V2_WITHDRAW_ALL_MARGIN = 1
    enum Command {
        ACCOUNT_MODIFY_MARGIN,
        ACCOUNT_WITHDRAW_ETH,
        PERPS_V2_MODIFY_MARGIN,
        PERPS_V2_WITHDRAW_ALL_MARGIN,
        PERPS_V2_SUBMIT_ATOMIC_ORDER,
        PERPS_V2_SUBMIT_DELAYED_ORDER,
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CANCEL_DELAYED_ORDER,
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CLOSE_POSITION,
        GELATO_PLACE_CONDITIONAL_ORDER,
        GELATO_CANCEL_CONDITIONAL_ORDER
    }

    /// @notice denotes conditional order types for code clarity
    /// @dev under the hood LIMIT = 0, STOP = 1
    enum ConditionalOrderTypes {
        LIMIT,
        STOP
    }

    /// @notice denotes conditional order cancelled reasons for code clarity
    /// @dev under the hood CONDITIONAL_ORDER_CANCELLED_BY_USER = 0, CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY = 1
    enum ConditionalOrderCancelledReason {
        CONDITIONAL_ORDER_CANCELLED_BY_USER,
        CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
    }

    /// marketKey: Synthetix PerpsV2 Market id/key
    /// marginDelta: amount of margin to deposit or withdraw; positive indicates deposit, negative withdraw
    /// sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of Synthetix PerpsV2 position
    /// targetPrice: limit or stop price to fill at
    /// gelatoTaskId: unqiue taskId from gelato necessary for cancelling conditional orders
    /// conditionalOrderType: conditional order type to determine conditional order fill logic
    /// priceImpactDelta: price impact tolerance as a percentage used on fillPrice at execution
    /// reduceOnly: if true, only allows position's absolute size to decrease
    struct ConditionalOrder {
        bytes32 marketKey;
        int256 marginDelta;
        int256 sizeDelta;
        uint256 targetPrice;
        bytes32 gelatoTaskId;
        ConditionalOrderTypes conditionalOrderType;
        uint128 priceImpactDelta;
        bool reduceOnly;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when commands length does not equal inputs length
    error LengthMismatch();

    /// @notice thrown when Command given is not valid
    error InvalidCommandType(uint256 commandType);

    /// @notice thrown when margin asset transfer fails
    error FailedMarginTransfer();

    /// @notice given value cannot be zero
    /// @param valueName: name of the variable that cannot be zero
    error ValueCannotBeZero(bytes32 valueName);

    /// @notice exceeds useable margin
    /// @param available: amount of useable margin asset
    /// @param required: amount of margin asset required
    error InsufficientFreeMargin(uint256 available, uint256 required);

    /// @notice call to transfer ETH on withdrawal fails
    error EthWithdrawalFailed();

    /// @notice base price from the oracle was invalid
    /// @dev Rate can be invalid either due to:
    ///     1. Returned as invalid from ExchangeRates - due to being stale or flagged by oracle
    ///     2. Out of deviation bounds w.r.t. to previously stored rate
    ///     3. if there is no valid stored rate, w.r.t. to previous 3 oracle rates
    ///     4. Price is zero
    error InvalidPrice();

    /// @notice Insufficient margin to pay fee
    error CannotPayFee();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice returns the version of the Account
    function VERSION() external view returns (bytes32);

    /// @return returns the address of the factory
    function factory() external view returns (IFactory);

    /// @return returns the address of the futures market manager
    function futuresMarketManager() external view returns (IFuturesMarketManager);

    /// @return returns the address of the native settings for account
    function settings() external view returns (ISettings);

    /// @return returns the address of events contract for accounts
    function events() external view returns (IEvents);

    /// @return returns the amount of margin locked for future events (i.e. conditional orders)
    function committedMargin() external view returns (uint256);

    /// @return returns current conditional order id
    function conditionalOrderId() external view returns (uint256);

    /// @notice get delayed order data from Synthetix PerpsV2
    /// @dev call reverts if _marketKey is invalid
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return delayed order struct defining delayed order (will return empty struct if no delayed order exists)
    function getDelayedOrder(bytes32 _marketKey)
        external
        returns (IPerpsV2MarketConsolidated.DelayedOrder memory);

    /// @notice checker() is the Resolver for Gelato
    /// (see https://docs.gelato.network/developer-services/automate/guides/custom-logic-triggers/smart-contract-resolvers)
    /// @notice signal to a keeper that a conditional order is valid/invalid for execution
    /// @dev call reverts if conditional order Id does not map to a valid conditional order;
    /// ConditionalOrder.marketKey would be invalid
    /// @param _conditionalOrderId: key for an active conditional order
    /// @return canExec boolean that signals to keeper a conditional order can be executed by Gelato
    /// @return execPayload calldata for executing a conditional order
    function checker(uint256 _conditionalOrderId)
        external
        view
        returns (bool canExec, bytes memory execPayload);

    /// @notice the current withdrawable or usable balance
    /// @return free margin amount
    function freeMargin() external view returns (uint256);

    /// @notice get up-to-date position data from Synthetix PerpsV2
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return position struct defining current position
    function getPosition(bytes32 _marketKey)
        external
        returns (IPerpsV2MarketConsolidated.Position memory);

    /// @notice conditional order id mapped to conditional order
    /// @param _conditionalOrderId: id of conditional order
    /// @return conditional order
    function getConditionalOrder(uint256 _conditionalOrderId)
        external
        view
        returns (ConditionalOrder memory);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice executes commands along with provided inputs
    /// @param _commands: array of commands, each represented as an enum
    /// @param _inputs: array of byte strings containing abi encoded inputs for each command
    function execute(Command[] calldata _commands, bytes[] calldata _inputs) external payable;

    /// @notice execute a gelato queued conditional order
    /// @notice only keepers can trigger this function
    /// @dev currently only supports conditional order submission via PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER COMMAND
    /// @param _conditionalOrderId: key for an active conditional order
    function executeConditionalOrder(uint256 _conditionalOrderId) external;
}
