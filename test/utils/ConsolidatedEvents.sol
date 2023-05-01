// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAccount} from "../../src/interfaces/IAccount.sol";

/// utility contract for *testing* events. consolidates all events into one contract

contract ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                IFACTORY
    //////////////////////////////////////////////////////////////*/

    event NewAccount(
        address indexed creator, address indexed account, bytes32 version
    );

    event AccountImplementationUpgraded(address implementation);

    /*//////////////////////////////////////////////////////////////
                                 IAUTH
    //////////////////////////////////////////////////////////////*/

    event OwnershipTransferred(
        address indexed caller, address indexed newOwner
    );

    event DelegatedAccountAdded(
        address indexed caller, address indexed delegate
    );

    event DelegatedAccountRemoved(
        address indexed caller, address indexed delegate
    );

    /*//////////////////////////////////////////////////////////////
                                IEVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed user, address indexed account, uint256 amount
    );

    event Withdraw(
        address indexed user, address indexed account, uint256 amount
    );

    event EthWithdraw(
        address indexed user, address indexed account, uint256 amount
    );

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

    event ConditionalOrderCancelled(
        address indexed account,
        uint256 indexed conditionalOrderId,
        bytes32 indexed gelatoTaskId,
        IAccount.ConditionalOrderCancelledReason reason
    );

    event ConditionalOrderFilled(
        address indexed account,
        uint256 indexed conditionalOrderId,
        bytes32 indexed gelatoTaskId,
        uint256 fillPrice,
        uint256 keeperFee
    );

    /*//////////////////////////////////////////////////////////////
                               ISETTINGS
    //////////////////////////////////////////////////////////////*/

    event AccountExecutionEnabledSet(bool enabled);
}
