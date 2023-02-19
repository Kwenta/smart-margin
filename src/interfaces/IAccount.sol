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
        PERPS_V2_MODIFY_MARGIN,
        PERPS_V2_WITHDRAW_ALL_MARGIN,
        PERPS_V2_SUBMIT_ATOMIC_ORDER,
        PERPS_V2_SUBMIT_DELAYED_ORDER,
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CANCEL_DELAYED_ORDER,
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CLOSE_POSITION
    }

    /// @notice denotes conditional order types for code clarity
    /// @dev under the hood LIMIT = 0, STOP = 1
    enum ConditionalOrderTypes {
        LIMIT,
        STOP
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
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful deposit
    /// @param user: the address that deposited into account
    /// @param account: the account that received the deposit
    /// @param amount: amount of marginAsset deposited into account
    event Deposit(address indexed user, address indexed account, uint256 amount);

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param account: the account that was withdrawn from
    /// @param amount: amount of marginAsset withdrawn from account
    event Withdraw(address indexed user, address indexed account, uint256 amount);

    /// @notice emitted after a successful ETH withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: the account that was withdrawn from
    /// @param amount: amount of ETH withdrawn from account
    event EthWithdraw(address indexed user, address indexed account, uint256 amount);

    /// @notice emitted when a conditional order is placed
    /// @param account: account placing the conditional order
    /// @param conditionalOrderId: id of conditional order
    /// @param marketKey: Synthetix PerpsV2 market key
    /// @param marginDelta: margin change
    /// @param sizeDelta: size change
    /// @param targetPrice: targeted fill price
    /// @param conditionalOrderType: expected conditional order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param priceImpactDelta: price impact tolerance as a percentage
    /// @param reduceOnly: if true, only allows position's absolute size to decrease
    event ConditionalOrderPlaced(
        address indexed account,
        uint256 conditionalOrderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        ConditionalOrderTypes conditionalOrderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    );

    /// @notice emitted when a conditional order is cancelled
    /// @param account: account cancelling the conditional order
    /// @param conditionalOrderId: id of conditional order
    event ConditionalOrderCancelled(address indexed account, uint256 conditionalOrderId);

    /// @notice emitted when a conditional order is filled
    /// @param account: account that placed the conditional order
    /// @param conditionalOrderId: id of conditional order
    /// @param fillPrice: price the conditional order was executed at
    /// @param keeperFee: fees paid to the executor
    event ConditionalOrderFilled(
        address indexed account, uint256 conditionalOrderId, uint256 fillPrice, uint256 keeperFee
    );

    /// @notice emitted after a fee has been transferred to Treasury
    /// @param account: the address of the account the fee was imposed on
    /// @param amount: fee amount sent to Treasury
    event FeeImposed(address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when commands length does not equal inputs length
    error LengthMismatch();

    /// @notice thrown when Command given is not valid
    error InvalidCommandType(uint256 commandType);

    /// @notice thrown when margin delta is
    /// positive/zero for withdrawals or negative/zero for deposits
    error InvalidMarginDelta();

    /// @notice thrown when margin asset transfer fails
    error FailedMarginTransfer();

    /// @notice given value cannot be zero
    /// @param valueName: name of the variable that cannot be zero
    error ValueCannotBeZero(bytes32 valueName);

    /// @notice exceeds useable margin
    /// @param available: amount of useable margin asset
    /// @param required: amount of margin asset required
    error InsufficientFreeMargin(uint256 available, uint256 required);

    /// @notice cannot execute invalid conditional order
    error ConditionalOrderInvalid();

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

    /// @notice Must have a minimum eth balance before placing a conditional order
    /// @param balance: current ETH balance
    /// @param minimum: min required ETH balance
    error InsufficientEthBalance(uint256 balance, uint256 minimum);

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

    /// @notice signal to a keeper that a conditional order is valid/invalid for execution
    /// @dev call reverts if conditional order Id does not map to a valid conditional order;
    /// ConditionalOrder.marketKey would be invalid
    /// @param _conditionalOrderId: key for an active conditional order
    /// @return canExec boolean that signals to keeper a conditional order can be executed
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

    /// @notice deposit margin asset to trade with into this contract
    /// @param _amount: amount of marginAsset to deposit into account
    function deposit(uint256 _amount) external;

    /// @notice attmept to withdraw non-committed margin from account to user
    /// @param _amount: amount of marginAsset to withdraw from account
    function withdraw(uint256 _amount) external;

    /// @notice allow users to withdraw ETH deposited for keeper fees
    /// @param _amount: amount to withdraw
    function withdrawEth(uint256 _amount) external;

    /// @notice executes commands along with provided inputs
    /// @param _commands: array of commands, each represented as an enum
    /// @param _inputs: array of byte strings containing abi encoded inputs for each command
    function execute(Command[] calldata _commands, bytes[] calldata _inputs) external payable;

    /// @notice register a conditional order internally and with gelato
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of position
    /// @param _targetPrice: expected conditional order price
    /// @param _conditionalOrderType: expected conditional order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @param _reduceOnly: if true, only allows position's absolute size to decrease
    /// @return id of newly created conditional order
    function placeConditionalOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        ConditionalOrderTypes _conditionalOrderType,
        uint128 _priceImpactDelta,
        bool _reduceOnly
    ) external payable returns (uint256);

    /// @notice cancel a gelato queued conditional order
    /// @param _conditionalOrderId: key for an active conditional order
    function cancelConditionalOrder(uint256 _conditionalOrderId) external;

    /// @notice execute a gelato queued conditional order
    /// @notice only keepers can trigger this function
    /// @dev currently only supports conditional order submission via PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER COMMAND
    /// @param _conditionalOrderId: key for an active conditional order
    function executeConditionalOrder(uint256 _conditionalOrderId) external;
}
