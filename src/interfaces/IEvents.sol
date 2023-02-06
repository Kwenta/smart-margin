// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IAccount} from "./IAccount.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @author JaredBorders (jaredborders@proton.me)
interface IEvents {
    event Deposit(address indexed account, uint256 amountDeposited);
    event Withdraw(address indexed account, uint256 amountWithdrawn);
    event EthWithdraw(address indexed account, uint256 amountWithdrawn);
    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.OrderTypes orderType,
        uint128 priceImpactDelta,
        uint256 maxDynamicFee
    );
    event OrderCancelled(address indexed account, uint256 orderId);
    event OrderFilled(
        address indexed account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    );
    event FeeImposed(address indexed account, uint256 amount);

    function emitDeposit(address account, uint256 amountDeposited) external;

    function emitWithdraw(address account, uint256 amountWithdrawn) external;

    function emitEthWithdraw(address account, uint256 amountWithdrawn) external;

    function emitOrderPlaced(
        address account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.OrderTypes orderType,
        uint128 priceImpactDelta,
        uint256 maxDynamicFee
    ) external;

    function emitOrderCancelled(address account, uint256 orderId) external;

    function emitOrderFilled(
        address account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    ) external;

    function emitFeeImposed(address account, uint256 amount) external;
}
