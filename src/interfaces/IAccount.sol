// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IPerpsV2MarketConsolidated} from
    "src/interfaces/synthetix/IPerpsV2MarketConsolidated.sol";

/// @title Kwenta Smart Margin Account v2.0.3 Implementation Interface
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IAccount {
    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    /// @notice Command Flags used to decode commands to execute
    /// @dev under the hood ACCOUNT_MODIFY_MARGIN = 0, ACCOUNT_WITHDRAW_ETH = 1
    enum Command {
        ACCOUNT_MODIFY_MARGIN, // 0
        ACCOUNT_WITHDRAW_ETH,
        UNISWAP_V3_SWAP,
        PERMIT2_PERMIT,
        PERPS_V2_MODIFY_MARGIN,
        PERPS_V2_WITHDRAW_ALL_MARGIN, // 5
        PERPS_V2_SUBMIT_ATOMIC_ORDER,
        PERPS_V2_SUBMIT_DELAYED_ORDER,
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CLOSE_POSITION,
        PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER, // 10
        PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CANCEL_DELAYED_ORDER,
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER,
        GELATO_PLACE_CONDITIONAL_ORDER,
        GELATO_CANCEL_CONDITIONAL_ORDER // 15
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

    /// @notice denotes what oracle is used for price when executing conditional orders
    /// @dev under the hood PYTH = 0, CHAINLINK = 1
    enum PriceOracleUsed {
        PYTH,
        CHAINLINK
    }

    /// @param factory: address of the Smart Margin Account Factory
    /// @param events: address of the contract used by all accounts for emitting events
    /// @param marginAsset: address of the Synthetix ProxyERC20sUSD contract used as the margin asset
    /// @param perpsV2ExchangeRate: address of the Synthetix PerpsV2ExchangeRate
    /// @param futuresMarketManager: address of the Synthetix FuturesMarketManager
    /// @param systemStatus: address of the Synthetix SystemStatus
    /// @param gelato: address of Gelato
    /// @param ops: address of Ops
    /// @param settings: address of contract used to store global settings
    /// @param universalRouter: address of Uniswap's Universal Router
    /// @param permit2: address of Uniswap's Permit2
    struct AccountConstructorParams {
        address factory;
        address events;
        address marginAsset;
        address perpsV2ExchangeRate;
        address futuresMarketManager;
        address systemStatus;
        address gelato;
        address ops;
        address settings;
        address universalRouter;
        address permit2;
    }

    /// marketKey: Synthetix PerpsV2 Market id/key
    /// marginDelta: amount of margin to deposit or withdraw; positive indicates deposit, negative withdraw
    /// sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of Synthetix PerpsV2 position
    /// targetPrice: limit or stop price target needing to be met to submit Synthetix PerpsV2 order
    /// gelatoTaskId: unqiue taskId from gelato necessary for cancelling conditional orders
    /// conditionalOrderType: conditional order type to determine conditional order fill logic
    /// desiredFillPrice: desired price to fill Synthetix PerpsV2 order at execution time
    /// reduceOnly: if true, only allows position's absolute size to decrease
    struct ConditionalOrder {
        bytes32 marketKey;
        int256 marginDelta;
        int256 sizeDelta;
        uint256 targetPrice;
        bytes32 gelatoTaskId;
        ConditionalOrderTypes conditionalOrderType;
        uint256 desiredFillPrice;
        bool reduceOnly;
    }
    /// @dev see example below elucidating targtPrice vs desiredFillPrice:
    /// 1. targetPrice met (ex: targetPrice = X)
    /// 2. account submits delayed order to Synthetix PerpsV2 with desiredFillPrice = Y
    /// 3. keeper executes Synthetix PerpsV2 order after delay period
    /// 4. if current market price defined by Synthetix PerpsV2
    ///    after delay period satisfies desiredFillPrice order is filled

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when commands length does not equal inputs length
    error LengthMismatch();

    /// @notice thrown when Command given is not valid
    error InvalidCommandType(uint256 commandType);

    /// @notice thrown when conditional order type given is not valid due to zero sizeDelta
    error ZeroSizeDelta();

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

    /// @notice thrown when account execution has been disabled in the settings contract
    error AccountExecutionDisabled();

    /// @notice thrown when a call attempts to reenter the protected function
    error Reentrancy();

    /// @notice thrown when token swap attempted with invalid token (i.e. token that is not whitelisted)
    /// @param tokenIn: token attempting to swap from
    /// @param tokenOut: token attempting to swap to
    error TokenSwapNotAllowed(address tokenIn, address tokenOut);

    /// @notice thrown when a conditional order is attempted to be executed during invalid market conditions
    /// @param conditionalOrderId: conditional order id
    /// @param executor: address of executor
    error CannotExecuteConditionalOrder(
        uint256 conditionalOrderId, address executor
    );

    /// @notice thrown when a conditional order is attempted to be executed but SM account cannot pay fee
    /// @param executorFee: fee required to execute conditional order
    error CannotPayExecutorFee(uint256 executorFee, address executor);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice returns the version of the Account
    function VERSION() external view returns (bytes32);

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

    /// @notice sets the initial owner of the account
    /// @dev only called once by the factory on account creation
    /// @param _owner: address of the owner
    function setInitialOwnership(address _owner) external;

    /// @notice executes commands along with provided inputs
    /// @param _commands: array of commands, each represented as an enum
    /// @param _inputs: array of byte strings containing abi encoded inputs for each command
    function execute(Command[] calldata _commands, bytes[] calldata _inputs)
        external
        payable;

    /// @notice execute queued conditional order
    /// @dev currently only supports conditional order submission via PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER COMMAND
    /// @param _conditionalOrderId: key for an active conditional order
    function executeConditionalOrder(uint256 _conditionalOrderId) external;
}
