// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Settings} from "src/Settings.sol";

import {ISettings} from "src/interfaces/ISettings.sol";

import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";

import {MARGIN_ASSET, USER} from "test/utils/Constants.sol";

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
                              EXECUTOR FEE
    //////////////////////////////////////////////////////////////*/

    function test_setExecutorFee(uint256 fee) public {
        settings.setExecutorFee(fee);
        assertEq(settings.executorFee(), fee);
    }

    function test_setExecutorFee_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setExecutorFee(1 ether / 100);
    }

    function test_setExecutorFee_Event() public {
        vm.expectEmit(true, true, true, true);
        emit ExecutorFeeSet(1 ether / 100);
        settings.setExecutorFee(1 ether / 100);
    }

    /*//////////////////////////////////////////////////////////////
                          WHITELISTING TOKENS
    //////////////////////////////////////////////////////////////*/

    function test_whitelistedTokens() public {
        assertEq(settings.isTokenWhitelisted(MARGIN_ASSET), false);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
        assertEq(settings.isTokenWhitelisted(MARGIN_ASSET), true);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, false);
        assertEq(settings.isTokenWhitelisted(MARGIN_ASSET), false);
    }

    function test_setTokenWhitelistStatus_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
    }

    function test_setTokenWhitelistStatus(address token) public {
        assertEq(settings.isTokenWhitelisted(token), false);
        settings.setTokenWhitelistStatus(token, true);
        assertEq(settings.isTokenWhitelisted(token), true);
        settings.setTokenWhitelistStatus(token, false);
        assertEq(settings.isTokenWhitelisted(token), false);
    }

    function test_setTokenWhitelistStatus_Event() public {
        vm.expectEmit(true, true, true, true);
        emit TokenWhitelistStatusUpdated(MARGIN_ASSET, true);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, true);
        vm.expectEmit(true, true, true, true);
        emit TokenWhitelistStatusUpdated(MARGIN_ASSET, false);
        settings.setTokenWhitelistStatus(MARGIN_ASSET, false);
    }

    /*//////////////////////////////////////////////////////////////
                             ORDER FLOW FEE
    //////////////////////////////////////////////////////////////*/

    function test_setOrderFlowFee(uint256 fee) public {
        if (fee > settings.MAX_ORDER_FLOW_FEE()) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.InvalidOrderFlowFee.selector)
            );
            settings.setOrderFlowFee(fee);
        } else {
            settings.setOrderFlowFee(fee);
            assertEq(settings.orderFlowFee(), fee);
        }
    }

    function test_setOrderFlowFee_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setExecutorFee(5);
    }

    function test_setOrderFlowFee_Event() public {
        vm.expectEmit(true, true, true, true);
        emit ExecutorFeeSet(5);
        settings.setExecutorFee(5);
    }
}
