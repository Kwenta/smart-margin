// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAccount, IEvents} from "src/interfaces/IEvents.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/// @title Consolidates all events emitted by the Smart Margin Accounts
/// @dev restricted to only Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
/// @author Flocqst (florian@kwenta.io)
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
    function emitDeposit(address user, uint256 amount)
        external
        override
        onlyAccounts
    {
        emit Deposit({user: user, account: msg.sender, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitWithdraw(address user, uint256 amount)
        external
        override
        onlyAccounts
    {
        emit Withdraw({user: user, account: msg.sender, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitEthWithdraw(address user, uint256 amount)
        external
        override
        onlyAccounts
    {
        emit EthWithdraw({user: user, account: msg.sender, amount: amount});
    }

    /// @inheritdoc IEvents
    function emitUniswapV3Swap(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external override onlyAccounts {
        emit UniswapV3Swap({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });
    }

    /// @inheritdoc IEvents
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
    ) external override onlyAccounts {
        emit ConditionalOrderPlaced({
            account: msg.sender,
            conditionalOrderId: conditionalOrderId,
            gelatoTaskId: gelatoTaskId,
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
        uint256 conditionalOrderId,
        bytes32 gelatoTaskId,
        IAccount.ConditionalOrderCancelledReason reason
    ) external override onlyAccounts {
        emit ConditionalOrderCancelled({
            account: msg.sender,
            conditionalOrderId: conditionalOrderId,
            gelatoTaskId: gelatoTaskId,
            reason: reason
        });
    }

    /// @inheritdoc IEvents
    function emitConditionalOrderFilled(
        uint256 conditionalOrderId,
        bytes32 gelatoTaskId,
        uint256 fillPrice,
        uint256 keeperFee,
        IAccount.PriceOracleUsed priceOracle
    ) external override onlyAccounts {
        emit ConditionalOrderFilled({
            account: msg.sender,
            conditionalOrderId: conditionalOrderId,
            gelatoTaskId: gelatoTaskId,
            fillPrice: fillPrice,
            keeperFee: keeperFee,
            priceOracle: priceOracle
        });
    }

    /// @inheritdoc IEvents
    function emitOwnershipTransferred(address caller, address newOwner)
        external
        override
        onlyAccounts
    {
        emit OwnershipTransferred({caller: caller, newOwner: newOwner});
    }

    /// @inheritdoc IEvents
    function emitDelegatedAccountAdded(address caller, address delegate)
        external
        override
        onlyAccounts
    {
        emit DelegatedAccountAdded({caller: caller, delegate: delegate});
    }

    /// @inheritdoc IEvents
    function emitDelegatedAccountRemoved(address caller, address delegate)
        external
        override
        onlyAccounts
    {
        emit DelegatedAccountRemoved({caller: caller, delegate: delegate});
    }

    /// @inheritdoc IEvents
    function emitOrderFlowFeeImposed(uint256 amount)
        external
        override
        onlyAccounts
    {
        emit OrderFlowFeeImposed({account: msg.sender, amount: amount});
    }
}
