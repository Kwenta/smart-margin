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
        // select block number
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

    function testOwnerSet() public {
        assertEq(settings.owner(), address(this));
    }

    function testTreasurySet() public {
        assertEq(settings.treasury(), KWENTA_TREASURY);
    }

    function testTradeFeeSet() public {
        assertEq(settings.tradeFee(), TRADE_FEE);
    }

    function testLimitOrderFeeSet() public {
        assertEq(settings.limitOrderFee(), LIMIT_ORDER_FEE);
    }

    function testStopOrderFeeSet() public {
        assertEq(settings.stopOrderFee(), STOP_ORDER_FEE);
    }

    function testTradeFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ISettings.InvalidFee.selector, settings.MAX_BPS() + 1)
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: invalidFee,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_ORDER_FEE
        });
    }

    function testLimitOrderFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ISettings.InvalidFee.selector, settings.MAX_BPS() + 1)
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: invalidFee,
            _stopOrderFee: STOP_ORDER_FEE
        });
    }

    function testStopOrderFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ISettings.InvalidFee.selector, settings.MAX_BPS() + 1)
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: invalidFee
        });
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    function testSettingTreasuryAddress() public {
        settings.setTreasury(USER);
        assertTrue(settings.treasury() == USER);
    }

    function testFailSettingTreasuryAddressIfNotOwner() public {
        vm.prank(USER);
        settings.setTreasury(USER);
    }

    function testShouldFailSettingTreasuryAddressToZero() public {
        vm.expectRevert(abi.encodeWithSelector(ISettings.ZeroAddress.selector));
        settings.setTreasury(address(0));
    }

    function testSettingTreasuryAddressEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit TreasuryAddressChanged(USER);
        // event we get
        settings.setTreasury(USER);
    }

    /// @dev fuzz test
    function testSettingTradeFee(uint256 x) public {
        if (x == settings.tradeFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setTradeFee(x);
            return;
        }
        if (x > 10_000) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setTradeFee(x);
            return;
        }
        settings.setTradeFee(x);
        assertTrue(settings.tradeFee() == x);
    }

    function testFailSetTradeFeeIfNotOwner() public {
        vm.prank(USER);
        settings.setTradeFee(1 ether);
    }

    function testFailSetSameTradeFee() public {
        settings.setTradeFee(TRADE_FEE);
    }

    function testSettingTradeFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit TradeFeeChanged(TRADE_FEE * 2);
        // event we get
        settings.setTradeFee(TRADE_FEE * 2);
    }

    /// @dev fuzz test
    function testSettingLimitOrderFee(uint256 x) public {
        if (x == settings.limitOrderFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setLimitOrderFee(x);
            return;
        }

        if (x > 10_000) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setLimitOrderFee(x);
            return;
        }
        settings.setLimitOrderFee(x);
        assertTrue(settings.limitOrderFee() == x);
    }

    function testFailSetLimitOrderFeeIfNotOwner() public {
        vm.prank(USER);
        settings.setLimitOrderFee(1 ether);
    }

    function testFailSetSameLimitOrderFee() public {
        settings.setLimitOrderFee(LIMIT_ORDER_FEE);
    }

    function testSettingLimitOrderFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit LimitOrderFeeChanged(LIMIT_ORDER_FEE * 2);
        // event we get
        settings.setLimitOrderFee(LIMIT_ORDER_FEE * 2);
    }

    /// @dev fuzz test
    function testSettingStopOrderFee(uint256 x) public {
        if (x == settings.stopOrderFee()) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.DuplicateFee.selector));
            settings.setStopOrderFee(x);
            return;
        }

        if (x > 10_000) {
            vm.expectRevert(abi.encodeWithSelector(ISettings.InvalidFee.selector, x));
            settings.setStopOrderFee(x);
            return;
        }
        settings.setStopOrderFee(x);
        assertTrue(settings.stopOrderFee() == x);
    }

    function testFailSetStopOrderFeeIfNotOwner() public {
        vm.prank(USER);
        settings.setStopOrderFee(1 ether);
    }

    function testFailSetSameStopOrderFee() public {
        settings.setStopOrderFee(STOP_ORDER_FEE);
    }

    function testSettingStopOrderFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit StopOrderFeeChanged(STOP_ORDER_FEE * 2);
        // event we get
        settings.setStopOrderFee(STOP_ORDER_FEE * 2);
    }
}
