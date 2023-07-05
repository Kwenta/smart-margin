// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {AuthExposed} from "test/utils/AuthExposed.sol";

import {DELEGATE, USER} from "test/utils/Constants.sol";

contract AuthTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contract(s)
    AuthExposed private auth;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // deploy main contract(s)
        auth = new AuthExposed(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isOwner() public {
        // check owner
        assertEq(auth.isOwner(), true);

        // check non-owner
        vm.prank(USER);
        assertEq(auth.isOwner(), false);
    }

    function test_isAuth() public {
        // check authenticated caller
        assertEq(auth.isAuth(), true);

        // check unauthenticated caller
        vm.prank(USER);
        assertEq(auth.isAuth(), false);
    }

    function test_transferOwnership() public {
        // check owner
        assertEq(auth.owner(), address(this));

        // transfer ownership
        auth.transferOwnership(USER);

        // check new owner
        assertEq(auth.owner(), USER);
    }

    function test_addDelegate() public {
        // check delegates
        assertEq(auth.delegates(DELEGATE), false);

        // add delegate
        auth.addDelegate(DELEGATE);

        // check delegates
        assertEq(auth.delegates(DELEGATE), true);
    }

    function test_removeDelegate() public {
        // add delegate
        auth.addDelegate(DELEGATE);

        // remove delegate
        auth.removeDelegate(DELEGATE);

        assertEq(auth.delegates(DELEGATE), false);
    }
}
