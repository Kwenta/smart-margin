// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IAccount} from "./IAccount.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @author JaredBorders (jaredborders@proton.me)
interface IEvents {
    /// @notice emitted when a user deposits margin asset (sUSD) into their account
    /// @param account: address of the account that received the deposit
    /// @param amountDeposited: amount of sUSD deposited
    function emitDeposit(address account, uint256 amountDeposited) external;

    event Deposit(address indexed account, uint256 amountDeposited);

    /// @notice emitted when a user withdraws margin asset (sUSD) from their account
    /// @param account: address of the account that funds (sUSD) were withdrawn from
    /// @param amountWithdrawn: amount of sUSD withdrawn
    function emitWithdraw(address account, uint256 amountWithdrawn) external;

    event Withdraw(address indexed account, uint256 amountWithdrawn);

    /// @notice emitted when a user withdraws ETH from their account
    /// @param account: address of the account that funds (ETH) were withdrawn from
    /// @param amountWithdrawn: amount of ETH withdrawn
    function emitEthWithdraw(address account, uint256 amountWithdrawn) external;

    event EthWithdraw(address indexed account, uint256 amountWithdrawn);

    /// @notice emitted when an advanced order is placed
    /// @param account: account placing the order
    /// @param orderId: id of order
    /// @param marketKey: futures market key
    /// @param marginDelta: margin change
    /// @param sizeDelta: size change
    /// @param targetPrice: targeted fill price
    /// @param orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param priceImpactDelta: price impact tolerance as a percentage
    /// @param reduceOnly: if true, only allows position's absolute size to decrease
    function emitOrderPlaced(
        address account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.OrderTypes orderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    ) external;

    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.OrderTypes orderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    );

    /// @notice emitted when an advanced order is cancelled
    /// @param account: account cancelling the order
    /// @param orderId: id of order
    function emitOrderCancelled(address account, uint256 orderId) external;

    event OrderCancelled(address indexed account, uint256 orderId);

    /// @notice emitted when an advanced order is filled
    /// @param account: account that placed the order
    /// @param orderId: id of order
    /// @param fillPrice: price the order was executed at
    /// @param keeperFee: fees paid to the executor
    function emitOrderFilled(
        address account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    ) external;

    event OrderFilled(
        address indexed account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    );

    /// @notice emitted after a fee has been transferred to Treasury
    /// @param account: the address of the account the fee was imposed on
    /// @param amount: fee amount sent to Treasury
    function emitFeeImposed(address account, uint256 amount) external;

    event FeeImposed(address indexed account, uint256 amount);
}
