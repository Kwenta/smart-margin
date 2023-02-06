// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExchanger} from "@synthetix/IExchanger.sol";
import {IFactory} from "./IFactory.sol";
import {IFuturesMarketManager} from "@synthetix/IFuturesMarketManager.sol";
import {IPerpsV2MarketConsolidated} from "@synthetix/IPerpsV2MarketConsolidated.sol";
import {ISettings} from "./ISettings.sol";

/// @title Kwenta Smart Margin Account Interface
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IAccount {
    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    /// @notice Command Flags used to decode commands to execute
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

    // denotes order types for code clarity
    /// @dev under the hood LIMIT = 0, STOP = 1
    enum OrderTypes {
        LIMIT,
        STOP
    }

    // marketKey: Synthetix PerpsV2 Market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    struct NewPosition {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta; // difference in position
        uint128 priceImpactDelta; // price impact tolerance as a percentage used on fillPrice at execution
    }

    // marketKey: Synthetix PerpsV2 Market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    // targetPrice: limit or stop price to fill at
    // gelatoTaskId: unqiue taskId from gelato necessary for cancelling orders
    // orderType: order type to determine order fill logic
    // maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    struct Order {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
        uint256 targetPrice;
        bytes32 gelatoTaskId;
        OrderTypes orderType;
        uint256 maxDynamicFee;
        uint128 priceImpactDelta; // price impact tolerance as a percentage used on fillPrice at execution
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful deposit
    /// @param user: the address that deposited into account
    /// @param amount: amount of marginAsset to deposit into account
    event Deposit(address indexed user, uint256 amount);

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of marginAsset to withdraw from account
    event Withdraw(address indexed user, uint256 amount);

    /// @notice emitted after a successful ETH withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of ETH to withdraw from account
    event EthWithdraw(address indexed user, uint256 amount);

    /// @notice emitted when an advanced order is placed
    /// @param account: account placing the order
    /// @param orderId: id of order
    /// @param marketKey: futures market key
    /// @param marginDelta: margin change
    /// @param sizeDelta: size change
    /// @param targetPrice: targeted fill price
    /// @param orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param priceImpactDelta: price impact tolerance as a percentage
    /// @param maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        OrderTypes orderType,
        uint128 priceImpactDelta,
        uint256 maxDynamicFee
    );

    /// @notice emitted when an advanced order is cancelled
    event OrderCancelled(address indexed account, uint256 orderId);

    /// @notice emitted when an advanced order is filled
    /// @param fillPrice: price the order was executed at
    /// @param keeperFee: fees paid to the executor
    event OrderFilled(
        address indexed account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
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

    /// @notice cannot execute invalid order
    error OrderInvalid();

    /// @notice call to transfer ETH on withdrawal fails
    error EthWithdrawalFailed();

    /// @notice base price from the oracle was invalid
    /// @dev Rate can be invalid either due to:
    ///      1. Returned as invalid from ExchangeRates - due to being stale or flagged by oracle
    ///      2. Out of deviation bounds w.r.t. to previously stored rate
    ///      3. if there is no valid stored rate, w.r.t. to previous 3 oracle rates
    ///      4. Price is zero
    error InvalidPrice();

    /// @notice Insufficient margin to pay fee
    error CannotPayFee();

    /// @notice Must have a minimum eth balance before placing an order
    /// @param balance: current ETH balance
    /// @param minimum: min required ETH balance
    error InsufficientEthBalance(uint256 balance, uint256 minimum);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice returns the version of the Account
    function VERSION() external view returns (bytes32);

    /// @return returns the address of the Synthetix ReadProxyAddressResolver
    function ADDRESS_RESOLVER() external view returns (IAddressResolver);

    /// @return returns the address of the Synthetix ProxyERC20sUSD address used as the margin asset
    function MARGIN_ASSET() external view returns (IERC20);

    /// @return returns the address of the factory
    function factory() external view returns (IFactory);

    /// @return returns the address of the futures market manager
    function futuresMarketManager()
        external
        view
        returns (IFuturesMarketManager);

    /// @return returns the address of the native settings for account
    function settings() external view returns (ISettings);

    /// @return returns the amount of margin locked for future events (ie. limit orders)
    function committedMargin() external view returns (uint256);

    /// @return returns current order id
    function orderId() external view returns (uint256);

    /// @notice get delayed order data from Synthetix PerpsV2
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return order struct defining delayed order
    function getDelayedOrder(bytes32 _marketKey)
        external
        returns (IPerpsV2MarketConsolidated.DelayedOrder memory);

    /// @notice signal to a keeper that an order is valid/invalid for execution
    /// @param _orderId: key for an active order
    /// @return canExec boolean that signals to keeper an order can be executed
    /// @return execPayload calldata for executing an order
    function checker(uint256 _orderId)
        external
        view
        returns (bool canExec, bytes memory execPayload);

    /// @notice the current withdrawable or usable balance
    function freeMargin() external view returns (uint256);

    /// @notice get up-to-date position data from Synthetix PerpsV2
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return position struct defining current position
    function getPosition(bytes32 _marketKey)
        external
        returns (IPerpsV2MarketConsolidated.Position memory);

    /// @notice calculate fee based on both size and given market
    /// @param _sizeDelta: size delta of given trade
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _advancedOrderFee: additional fee charged for advanced orders
    /// @dev _advancedOrderFee will be zero if trade is not an advanced order
    /// @return fee to be imposed based on size delta
    function calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee
    ) external view returns (uint256);

    /// @notice order id mapped to order
    function getOrder(uint256 _orderId) external view returns (Order memory);

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
    function execute(Command[] calldata _commands, bytes[] calldata _inputs)
        external
        payable;

    /// @notice order logic condition checker
    /// @dev this is where order type logic checks are handled
    /// @param _orderId: key for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be filled at (only valid if prev is true)
    function validOrder(uint256 _orderId) external view returns (bool, uint256);

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _targetPrice: expected limit order price
    /// @param _orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @return orderId contract interface
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta
    ) external payable returns (uint256);

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _targetPrice: expected limit order price
    /// @param _orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @param _maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    /// @return orderId contract interface
    function placeOrderWithFeeCap(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta,
        uint256 _maxDynamicFee
    ) external payable returns (uint256);

    /// @notice cancel a gelato queued order
    /// @param _orderId: key for an active order
    function cancelOrder(uint256 _orderId) external;

    /// @notice execute a gelato queued order
    /// @notice only keepers can trigger this function
    /// @param _orderId: key for an active order
    function executeOrder(uint256 _orderId) external;
}
