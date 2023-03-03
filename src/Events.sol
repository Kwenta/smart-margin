// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IEvents, IAccount} from "./interfaces/IEvents.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
contract Events is IEvents {
    /// @inheritdoc IEvents
    function emitDeposit(address user, address account, uint256 amount) external override {
        emit Deposit({user: user, account: account, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitWithdraw(address user, address account, uint256 amount) external override {
        emit Withdraw({user: user, account: account, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitEthWithdraw(address user, address account, uint256 amount) external override {
        emit EthWithdraw({user: user, account: account, amount: amount});
    }

    /// @inheritdoc IEvents
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
    ) external override {
        emit ConditionalOrderPlaced({
            account: account,
            conditionalOrderId: conditionalOrderId,
            marketKey: marketKey,
            marginDelta: marginDelta,
            sizeDelta: sizeDelta,
            targetPrice: targetPrice,
            conditionalOrderType: conditionalOrderType,
            priceImpactDelta: priceImpactDelta,
            reduceOnly: reduceOnly
        });
    }

    /// @inheritdoc IEvents
    function emitConditionalOrderCancelled(
        address account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    ) external override {
        emit ConditionalOrderCancelled({
            account: account,
            conditionalOrderId: conditionalOrderId,
            reason: reason
        });
    }

    /// @inheritdoc IEvents
    function emitConditionalOrderFilled(
        address account,
        uint256 conditionalOrderId,
        uint256 fillPrice,
        uint256 keeperFee
    ) external override {
        emit ConditionalOrderFilled({
            account: account,
            conditionalOrderId: conditionalOrderId,
            fillPrice: fillPrice,
            keeperFee: keeperFee
        });
    }

    /// @inheritdoc IEvents
    function emitFeeImposed(address account, uint256 amount) external override {
        emit FeeImposed({account: account, amount: amount});
    }
}
