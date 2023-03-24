// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IEvents, IAccount} from "./interfaces/IEvents.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @dev restricted to only Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
contract Events is IEvents {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEvents
    address public immutable factory;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev modifier that restricts access to only accounts
    modifier onlyAccounts() {
        if (!IFactory(factory).accounts(msg.sender)) {
            revert OnlyAccounts();
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructs the Events contract
    /// @param _factory: address of the factory contract
    constructor(address _factory) {
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEvents
    function emitDeposit(address user, address account, uint256 amount)
        external
        override
        onlyAccounts
    {
        emit Deposit({user: user, account: account, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitWithdraw(address user, address account, uint256 amount)
        external
        override
        onlyAccounts
    {
        emit Withdraw({user: user, account: account, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitEthWithdraw(address user, address account, uint256 amount)
        external
        override
        onlyAccounts
    {
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
        uint128 desiredFillPrice,
        bool reduceOnly
    ) external override onlyAccounts {
        emit ConditionalOrderPlaced({
            account: account,
            conditionalOrderId: conditionalOrderId,
            marketKey: marketKey,
            marginDelta: marginDelta,
            sizeDelta: sizeDelta,
            targetPrice: targetPrice,
            conditionalOrderType: conditionalOrderType,
            desiredFillPrice: desiredFillPrice,
            reduceOnly: reduceOnly
        });
    }

    /// @inheritdoc IEvents
    function emitConditionalOrderCancelled(
        address account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    ) external override onlyAccounts {
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
        uint256 keeperFee,
        uint256 kwentaFee
    ) external override onlyAccounts {
        emit ConditionalOrderFilled({
            account: account,
            conditionalOrderId: conditionalOrderId,
            fillPrice: fillPrice,
            keeperFee: keeperFee,
            kwentaFee: kwentaFee
        });
    }

    /// @inheritdoc IEvents
    function emitFeeImposed(
        address account,
        uint256 amount,
        bytes32 marketKey,
        bytes32 reason
    ) external override onlyAccounts {
        emit FeeImposed({
            account: account,
            amount: amount,
            marketKey: marketKey,
            reason: reason
        });
    }
}
