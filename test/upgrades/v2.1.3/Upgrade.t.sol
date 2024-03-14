// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {AccountExposed} from "test/utils/AccountExposed.sol";

/// @notice Test mutable storage slots are not changed in
/// Account contract to ensure upgrade safety
contract UpgradeTest is Test {
    AccountExposed private accountExposed;

    /*//////////////////////////////////////////////////////////////
                                 SLOTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant OWNER_SLOT = 0;
    uint256 internal constant DELEGATES_SLOT = 1;
    uint256 internal constant COMMITTED_MARGIN_SLOT = 21;
    uint256 internal constant CONDITIONAL_ORDER_ID_SLOT = 22;
    uint256 internal constant CONDITIONAL_ORDERS_SLOT = 23;
    uint256 internal constant LOCKED_SLOT = 24;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        IAccount.AccountConstructorParams memory params = IAccount
            .AccountConstructorParams(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        accountExposed = new AccountExposed(params);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_owner_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_owner_slot(), OWNER_SLOT, "slot missmatch"
        );
    }

    function test_delegates_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_delegates_slot(),
            DELEGATES_SLOT,
            "slot missmatch"
        );
    }

    function test_committedMargin_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_committedMargin_slot(),
            COMMITTED_MARGIN_SLOT,
            "slot missmatch"
        );
    }

    function test_conditionalOrderId_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_conditionalOrderId_slot(),
            CONDITIONAL_ORDER_ID_SLOT,
            "slot missmatch"
        );
    }

    function test_conditionalOrders_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_conditionalOrders_slot(),
            CONDITIONAL_ORDERS_SLOT,
            "slot missmatch"
        );
    }

    function test_locked_slot() public {
        /// @dev slot should NEVER change
        assertEq(
            accountExposed.expose_locked_slot(), LOCKED_SLOT, "slot missmatch"
        );
    }
}
