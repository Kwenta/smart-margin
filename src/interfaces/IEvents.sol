// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAccount} from "./IAccount.sol";

/// @title Interface for contract that emits all events emitted by the Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
interface IEvents {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when a non-account contract attempts to call a restricted function
    error OnlyAccounts();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice returns the address of the factory contract
    function factory() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of marginAsset to withdraw from account
    function emitDeposit(address user, uint256 amount) external;

    event Deposit(
        address indexed user, address indexed account, uint256 amount
    );

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of marginAsset to withdraw from account
    function emitWithdraw(address user, uint256 amount) external;

    event Withdraw(
        address indexed user, address indexed account, uint256 amount
    );

    /// @notice emitted after a successful ETH withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of ETH to withdraw from account
    function emitEthWithdraw(address user, uint256 amount) external;

    event EthWithdraw(
        address indexed user, address indexed account, uint256 amount
    );

    /// @notice emitted after a successful token swap
    /// @param tokenIn: contract address of the inbound token
    /// @param tokenOut: contract address of the outbound token
    /// @param recipient: address to receive the outbound token
    /// @param amountIn: amount of inbound token to swap
    /// @param amountOutMinimum: minimum amount of outbound token to receive
    function emitUniswapV3Swap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external;

    event UniswapV3Swap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    );

    /// @notice emitted when a conditional order is placed
    /// @param conditionalOrderId: id of conditional order
    /// @param gelatoTaskId: id of gelato task
    /// @param marketKey: Synthetix PerpsV2 market key
    /// @param marginDelta: margin change
    /// @param sizeDelta: size change
    /// @param targetPrice: targeted fill price
    /// @param conditionalOrderType: expected conditional order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param desiredFillPrice: desired price to fill Synthetix PerpsV2 order at execution time
    /// @param reduceOnly: if true, only allows position's absolute size to decrease
    function emitConditionalOrderPlaced(
        uint256 conditionalOrderId,
        bytes32 gelatoTaskId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint256 desiredFillPrice,
        bool reduceOnly
    ) external;

    event ConditionalOrderPlaced(
        address indexed account,
        uint256 indexed conditionalOrderId,
        bytes32 indexed gelatoTaskId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint256 desiredFillPrice,
        bool reduceOnly
    );

    /// @notice emitted when a conditional order is cancelled
    /// @param conditionalOrderId: id of conditional order
    /// @param gelatoTaskId: id of gelato task
    /// @param reason: reason for cancellation
    function emitConditionalOrderCancelled(
        uint256 conditionalOrderId,
        bytes32 gelatoTaskId,
        IAccount.ConditionalOrderCancelledReason reason
    ) external;

    event ConditionalOrderCancelled(
        address indexed account,
        uint256 indexed conditionalOrderId,
        bytes32 indexed gelatoTaskId,
        IAccount.ConditionalOrderCancelledReason reason
    );

    /// @notice emitted when a conditional order is filled
    /// @param conditionalOrderId: id of conditional order
    /// @param gelatoTaskId: id of gelato task
    /// @param fillPrice: price the conditional order was executed at
    /// @param keeperFee: fees paid to the executor
    /// @param priceOracle: price oracle used to execute conditional order
    function emitConditionalOrderFilled(
        uint256 conditionalOrderId,
        bytes32 gelatoTaskId,
        uint256 fillPrice,
        uint256 keeperFee,
        IAccount.PriceOracleUsed priceOracle
    ) external;

    event ConditionalOrderFilled(
        address indexed account,
        uint256 indexed conditionalOrderId,
        bytes32 indexed gelatoTaskId,
        uint256 fillPrice,
        uint256 keeperFee,
        IAccount.PriceOracleUsed priceOracle
    );

    /// @notice emitted after ownership transfer
    /// @param caller: previous owner
    /// @param newOwner: new owner
    function emitOwnershipTransferred(address caller, address newOwner)
        external;

    event OwnershipTransferred(
        address indexed caller, address indexed newOwner
    );

    /// @notice emitted after a delegate is added
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being added
    function emitDelegatedAccountAdded(address caller, address delegate)
        external;

    event DelegatedAccountAdded(
        address indexed caller, address indexed delegate
    );

    /// @notice emitted after a delegate is removed
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being removed
    function emitDelegatedAccountRemoved(address caller, address delegate)
        external;

    event DelegatedAccountRemoved(
        address indexed caller, address indexed delegate
    );

    /// @custom:todo add event function for order flow fee imposed
    /// @custom:todo add event for order flow fee imposed
}
