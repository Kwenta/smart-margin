// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ISettings} from "../../src/interfaces/ISettings.sol";
import {Settings} from "../../src/Settings.sol";

contract SettingsTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    Settings private settings;

    address private constant KWENTA_TREASURY = address(0xA);
    address private constant RANDOM_ADDRESS = address(0xB);

    uint256 private tradeFee = 1;
    uint256 private limitOrderFee = 2;
    uint256 private stopOrderFee = 3;

    event TreasuryAddressChanged(address treasury);
    event TradeFeeChanged(uint256 fee);
    event LimitOrderFeeChanged(uint256 fee);
    event StopOrderFeeChanged(uint256 fee);

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopOrderFee
        });
    }

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
        assertEq(settings.tradeFee(), tradeFee);
    }

    function testLimitOrderFeeSet() public {
        assertEq(settings.limitOrderFee(), limitOrderFee);
    }

    function testStopOrderFeeSet() public {
        assertEq(settings.stopOrderFee(), stopOrderFee);
    }

    function testTradeFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISettings.InvalidFee.selector, settings.MAX_BPS() + 1
            )
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: invalidFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopOrderFee
        });
    }

    function testLimitOrderFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISettings.InvalidFee.selector, settings.MAX_BPS() + 1
            )
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: invalidFee,
            _stopOrderFee: stopOrderFee
        });
    }

    function testStopOrderFeeCannotExceedMaxBps() public {
        uint256 invalidFee = settings.MAX_BPS() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISettings.InvalidFee.selector, settings.MAX_BPS() + 1
            )
        );
        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: invalidFee
        });
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    function testSettingTreasuryAddress() public {
        settings.setTreasury(RANDOM_ADDRESS);
        assertTrue(settings.treasury() == RANDOM_ADDRESS);
    }

    function testFailSettingTreasuryAddressIfNotOwner() public {
        vm.prank(RANDOM_ADDRESS);
        settings.setTreasury(RANDOM_ADDRESS);
    }

    function testShouldFailSettingTreasuryAddressToZero() public {
        vm.expectRevert(abi.encodeWithSelector(ISettings.ZeroAddress.selector));
        settings.setTreasury(address(0));
    }

    function testSettingTreasuryAddressEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit TreasuryAddressChanged(RANDOM_ADDRESS);
        // event we get
        settings.setTreasury(RANDOM_ADDRESS);
    }

    /// @dev fuzz test
    function testSettingTradeFee(uint256 x) public {
        if (x == settings.tradeFee()) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.DuplicateFee.selector)
            );
            settings.setTradeFee(x);
            return;
        }
        if (x > 10_000) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.InvalidFee.selector, x)
            );
            settings.setTradeFee(x);
            return;
        }
        settings.setTradeFee(x);
        assertTrue(settings.tradeFee() == x);
    }

    function testFailSetTradeFeeIfNotOwner() public {
        vm.prank(RANDOM_ADDRESS);
        settings.setTradeFee(1 ether);
    }

    function testFailSetSameTradeFee() public {
        settings.setTradeFee(tradeFee);
    }

    function testSettingTradeFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit TradeFeeChanged(tradeFee * 2);
        // event we get
        settings.setTradeFee(tradeFee * 2);
    }

    /// @dev fuzz test
    function testSettingLimitOrderFee(uint256 x) public {
        if (x == settings.limitOrderFee()) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.DuplicateFee.selector)
            );
            settings.setLimitOrderFee(x);
            return;
        }

        if (x > 10_000) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.InvalidFee.selector, x)
            );
            settings.setLimitOrderFee(x);
            return;
        }
        settings.setLimitOrderFee(x);
        assertTrue(settings.limitOrderFee() == x);
    }

    function testFailSetLimitOrderFeeIfNotOwner() public {
        vm.prank(RANDOM_ADDRESS);
        settings.setLimitOrderFee(1 ether);
    }

    function testFailSetSameLimitOrderFee() public {
        settings.setLimitOrderFee(limitOrderFee);
    }

    function testSettingLimitOrderFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit LimitOrderFeeChanged(limitOrderFee * 2);
        // event we get
        settings.setLimitOrderFee(limitOrderFee * 2);
    }

    /// @dev fuzz test
    function testSettingStopOrderFee(uint256 x) public {
        if (x == settings.stopOrderFee()) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.DuplicateFee.selector)
            );
            settings.setStopOrderFee(x);
            return;
        }

        if (x > 10_000) {
            vm.expectRevert(
                abi.encodeWithSelector(ISettings.InvalidFee.selector, x)
            );
            settings.setStopOrderFee(x);
            return;
        }
        settings.setStopOrderFee(x);
        assertTrue(settings.stopOrderFee() == x);
    }

    function testFailSetStopOrderFeeIfNotOwner() public {
        vm.prank(RANDOM_ADDRESS);
        settings.setStopOrderFee(1 ether);
    }

    function testFailSetSameStopOrderFee() public {
        settings.setStopOrderFee(stopOrderFee);
    }

    function testSettingStopOrderFeeEvent() public {
        vm.expectEmit(true, true, true, true);
        // event we expect
        emit StopOrderFeeChanged(stopOrderFee * 2);
        // event we get
        settings.setStopOrderFee(stopOrderFee * 2);
    }
}
