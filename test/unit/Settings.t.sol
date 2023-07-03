// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Settings} from "../../src/Settings.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {MARGIN_ASSET, USER} from "../utils/Constants.sol";

contract SettingsTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Settings private settings;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        settings = new Settings(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Owner() public {
        assertEq(settings.owner(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                             EXECUTION LOCK
    //////////////////////////////////////////////////////////////*/

    function test_setAccountExecutionEnabled() public {
        assertEq(settings.accountExecutionEnabled(), true);
        settings.setAccountExecutionEnabled(false);
        assertEq(settings.accountExecutionEnabled(), false);
    }

    function test_setAccountExecutionEnabled_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setAccountExecutionEnabled(false);
    }

    function test_setAccountExecutionEnabled_Event() public {
        vm.expectEmit(true, true, true, true);
        emit AccountExecutionEnabledSet(false);
        settings.setAccountExecutionEnabled(false);
    }

    /*//////////////////////////////////////////////////////////////
                          WHITELISTING TOKENS
    //////////////////////////////////////////////////////////////*/

    function test_whitelistedTokens() public {
        assertEq(settings.whitelistedTokens(MARGIN_ASSET), false);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
        assertEq(settings.whitelistedTokens(MARGIN_ASSET), true);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, false);
        assertEq(settings.whitelistedTokens(MARGIN_ASSET), false);
    }

    function test_setTokenWhitelistStatus_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
    }

    function test_setTokenWhitelistStatus(address token) public {
        assertEq(settings.whitelistedTokens(token), false);
        settings.setTokenWhitelistStatus(token, true);
        assertEq(settings.whitelistedTokens(token), true);
        settings.setTokenWhitelistStatus(token, false);
        assertEq(settings.whitelistedTokens(token), false);
    }

    function test_setTokenWhitelistStatus_Event() public {
        vm.expectEmit(true, true, true, true);
        emit TokenWhitelistStatusUpdated(MARGIN_ASSET);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
    }
}
