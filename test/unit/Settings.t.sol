// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {ISettings} from "../../src/interfaces/ISettings.sol";
import {Settings} from "../../src/Settings.sol";
import "../utils/Constants.sol";

contract SettingsTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_ORDER_FEE
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_OwnerSet() public {
        assertEq(settings.owner(), address(this));
    }

    function test_TreasurySet() public {
        assertEq(settings.treasury(), KWENTA_TREASURY);
    }

    function test_TradeFeeSet() public {
        assertEq(settings.tradeFee(), TRADE_FEE);
    }

    function test_LimitOrderFeeSet() public {
        assertEq(settings.limitOrderFee(), LIMIT_ORDER_FEE);
    }

    function test_StopOrderFeeSet() public {
        assertEq(settings.stopOrderFee(), STOP_ORDER_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                               TRADE FEE
    //////////////////////////////////////////////////////////////*/

    function test_SetTradeFee(uint256 x) public {
        if (x == settings.tradeFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setTradeFee(x);
            return;
        } else if (x > settings.MAX_BPS()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setTradeFee(x);
            return;
        }
        settings.setTradeFee(x);
        assertTrue(settings.tradeFee() == x);
    }

    function test_SetTradeFee_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setTradeFee(1 ether);
    }

    function test_SetTradeFee_Event() public {
        vm.expectEmit(true, true, true, true);
        emit TradeFeeChanged(TRADE_FEE * 2);
        settings.setTradeFee(TRADE_FEE * 2);
    }

    /*//////////////////////////////////////////////////////////////
                            LIMIT ORDER FEE
    //////////////////////////////////////////////////////////////*/

    function test_SetLimitOrderFee(uint256 x) public {
        if (x == settings.limitOrderFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setLimitOrderFee(x);
            return;
        } else if (x > settings.MAX_BPS()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setLimitOrderFee(x);
            return;
        }
        settings.setLimitOrderFee(x);
        assertTrue(settings.limitOrderFee() == x);
    }

    function test_SetLimitOrderFee_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setLimitOrderFee(1 ether);
    }

    function test_SetLimitOrderFee_Event() public {
        vm.expectEmit(true, true, true, true);
        emit LimitOrderFeeChanged(LIMIT_ORDER_FEE * 2);
        settings.setLimitOrderFee(LIMIT_ORDER_FEE * 2);
    }

    /*//////////////////////////////////////////////////////////////
                             STOP ORDER FEE
    //////////////////////////////////////////////////////////////*/

    function test_SetStopOrderFee(uint256 x) public {
        if (x == settings.stopOrderFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setStopOrderFee(x);
            return;
        } else if (x > settings.MAX_BPS()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setStopOrderFee(x);
            return;
        }
        settings.setStopOrderFee(x);
        assertTrue(settings.stopOrderFee() == x);
    }

    function test_SetStopOrderFee_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setStopOrderFee(1 ether);
    }

    function test_SetStopOrderFee_Event() public {
        vm.expectEmit(true, true, true, true);
        emit StopOrderFeeChanged(STOP_ORDER_FEE * 2);
        settings.setStopOrderFee(STOP_ORDER_FEE * 2);
    }

    /*//////////////////////////////////////////////////////////////
                              SET TREASURY
    //////////////////////////////////////////////////////////////*/

    function test_SetTreasury(address addr) public {
        if (addr == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.ZeroAddress.selector));
            settings.setTreasury(addr);
            return;
        } else if (addr == settings.treasury()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateAddress.selector));
            settings.setTreasury(addr);
            return;
        }
        settings.setTreasury(addr);
        assertTrue(settings.treasury() == addr);
    }

    function test_SetTreasury_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(USER);
        settings.setTreasury(USER);
    }

    function test_SetTreasury_Event() public {
        vm.expectEmit(true, true, true, true);
        emit TreasuryAddressChanged(USER);
        settings.setTreasury(USER);
        assertTrue(settings.treasury() == USER);
    }
}
