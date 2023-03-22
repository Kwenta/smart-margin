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
    /// @param account: the account that was withdrawn from
    /// @param amount: amount of marginAsset to withdraw from account
    function emitDeposit(address user, address account, uint256 amount)
        external;

    event Deposit(
        address indexed user, address indexed account, uint256 amount
    );

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param account: the account that was withdrawn from
    /// @param amount: amount of marginAsset to withdraw from account
    function emitWithdraw(address user, address account, uint256 amount)
        external;

    event Withdraw(
        address indexed user, address indexed account, uint256 amount
    );

    /// @notice emitted after a successful ETH withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: the account that was withdrawn from
    /// @param amount: amount of ETH to withdraw from account
    function emitEthWithdraw(address user, address account, uint256 amount)
        external;

    event EthWithdraw(
        address indexed user, address indexed account, uint256 amount
    );

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
    function emitConditionalOrderPlaced(
        address account,
        uint256 conditionalOrderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    ) external;

    event ConditionalOrderPlaced(
        address indexed account,
        uint256 conditionalOrderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    );

    /// @notice emitted when a conditional order is cancelled
    /// @param account: account cancelling the conditional order
    /// @param conditionalOrderId: id of conditional order
    /// @param reason: reason for cancellation
    function emitConditionalOrderCancelled(
        address account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    ) external;

    event ConditionalOrderCancelled(
        address indexed account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    );

    /// @notice emitted when a conditional order is filled
    /// @param account: account that placed the conditional order
    /// @param conditionalOrderId: id of conditional order
    /// @param fillPrice: price the conditional order was executed at
    /// @param keeperFee: fees paid to the executor
    function emitConditionalOrderFilled(
        address account,
        uint256 conditionalOrderId,
        uint256 fillPrice,
        uint256 keeperFee
    ) external;

    event ConditionalOrderFilled(
        address indexed account,
        uint256 conditionalOrderId,
        uint256 fillPrice,
        uint256 keeperFee
    );

    /// @notice emitted after a fee has been transferred to Treasury
    /// @param account: the address of the account the fee was imposed on
    /// @param amount: fee amount sent to Treasury
    /// @param marketKey: Synthetix PerpsV2 market key
    /// @param reason: reason for fee
    function emitFeeImposed(
        address account,
        uint256 amount,
        bytes32 marketKey,
        bytes32 reason
    ) external;

    event FeeImposed(
        address account, uint256 amount, bytes32 marketKey, bytes32 reason
    );
}
