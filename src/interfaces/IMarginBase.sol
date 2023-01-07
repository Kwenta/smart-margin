// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IMarginBaseTypes.sol";
import "@synthetix/IPerpsV2MarketConsolidated.sol";

/// @title Kwenta MarginBase Interface
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IMarginBase is IMarginBaseTypes {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful deposit
    /// @param user: the address that deposited into account
    /// @param amount: amount of marginAsset to deposit into marginBase account
    event Deposit(address indexed user, uint256 amount);

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of marginAsset to withdraw from marginBase account
    event Withdraw(address indexed user, uint256 amount);

    /// @notice emitted when an advanced order is placed
    /// @param account: account placing the order
    /// @param orderId: id of order
    /// @param marketKey: futures market key
    /// @param marginDelta: margin change
    /// @param sizeDelta: size change
    /// @param targetPrice: targeted fill price
    /// @param orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    /// @param priceImpactDelta: price impact tolerance as a percentage
    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        OrderTypes orderType,
        uint256 maxDynamicFee,
        uint128 priceImpactDelta
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

    /// @notice thrown when margin asset transfer fails
    error FailedMarginTransfer();

    /// @notice given value cannot be zero
    /// @param valueName: name of the variable that cannot be zero
    error ValueCannotBeZero(bytes32 valueName);

    /// @notice limit size of new position specs passed into distribute margin
    /// @param numberOfNewPositions: number of new position specs
    error MaxNewPositionsExceeded(uint256 numberOfNewPositions);

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

    /// @notice cannot rescue underlying margin asset token
    error CannotRescueMarginAsset();

    /// @notice Insufficient margin to pay fee
    error CannotPayFee();

    /// @notice Must have a minimum eth balance before placing an order
    /// @param balance: current ETH balance
    /// @param minimum: min required ETH balance
    error InsufficientEthBalance(uint256 balance, uint256 minimum);

    /*///////////////////////////////////////////////////////////////
                                Views
    ///////////////////////////////////////////////////////////////*/

    function freeMargin() external view returns (uint256);

    function getPosition(bytes32 _marketKey)
        external
        returns (IPerpsV2MarketConsolidated.Position memory);

    /*///////////////////////////////////////////////////////////////
                                Mutative
    ///////////////////////////////////////////////////////////////*/

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function withdrawEth(uint256 _amount) external;

    function distributeMargin(NewPosition[] memory _newPositions) external;

    function depositAndDistribute(
        uint256 _amount,
        NewPosition[] memory _newPositions
    ) external;

    function validOrder(uint256 _orderId) external view returns (bool, uint256);

    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta
    ) external payable returns (uint256);

    function placeOrderWithFeeCap(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint256 _maxDynamicFee,
        uint128 _priceImpactDelta
    ) external payable returns (uint256);

    function cancelOrder(uint256 _orderId) external;

    function checker(uint256 _orderId)
        external
        view
        returns (bool canExec, bytes memory execPayload);
}
