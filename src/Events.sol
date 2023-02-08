// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IEvents, IAccount} from "./interfaces/IEvents.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @author JaredBorders (jaredborders@proton.me)
contract Events is IEvents {
    function emitDeposit(address account, uint256 amountDeposited)
        external
        override
    {
        emit Deposit(account, amountDeposited);
    }

    function emitWithdraw(address account, uint256 amountWithdrawn)
        external
        override
    {
        emit Withdraw(account, amountWithdrawn);
    }

    function emitEthWithdraw(address account, uint256 amountWithdrawn)
        external
        override
    {
        emit EthWithdraw(account, amountWithdrawn);
    }

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
    ) external override {
        emit OrderPlaced(
            account,
            orderId,
            marketKey,
            marginDelta,
            sizeDelta,
            targetPrice,
            orderType,
            priceImpactDelta,
            maxDynamicFee
        );
    }

    function emitOrderCancelled(address account, uint256 orderId)
        external
        override
    {
        emit OrderCancelled(account, orderId);
    }

    function emitOrderFilled(
        address account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    ) external override {
        emit OrderFilled(account, orderId, fillPrice, keeperFee);
    }

    function emitFeeImposed(address account, uint256 amount) external override {
        emit FeeImposed(account, amount);
    }
}
