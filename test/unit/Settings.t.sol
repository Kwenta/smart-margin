// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../utils/Constants.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Settings} from "../../src/Settings.sol";

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
}
