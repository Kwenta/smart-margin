// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/Settings.sol";
import "../../src/interfaces/ISettings.sol";
import "../../src/Factory.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/Account.sol";
import "../../src/interfaces/IAccount.sol";

contract settingsTest is Test {
    Settings settings;

    address constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;
    address constant RANDOM_ADDRESS =
        0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

    uint256 private tradeFee = 5;
    uint256 private limitOrderFee = 5;
    uint256 private stopOrderFee = 10;

    event TreasuryAddressChanged(address treasury);
    event TradeFeeChanged(uint256 fee);
    event LimitOrderFeeChanged(uint256 fee);
    event StopOrderFeeChanged(uint256 fee);

    function setUp() public {
        settings = new Settings(
            KWENTA_TREASURY,
            tradeFee,
            limitOrderFee,
            stopOrderFee
        );
    }

    function testSettingsOwnerIsDeployer() public {
        assertEq(settings.owner(), address(this));
    }

    function testSettingTreasuryAddress() public {
        settings.setTreasury(RANDOM_ADDRESS);
        assertTrue(settings.treasury() == RANDOM_ADDRESS);
    }

    function testFailSettingTreasuryAddressIfNotOwner() public {
        settings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        settings.setTreasury(RANDOM_ADDRESS);
    }

    function testShouldFailSettingTreasuryAddressToZero() public {
        vm.expectRevert(abi.encodeWithSelector(ISettings.ZeroAddress.selector));
        settings.setTreasury(address(0));
    }

    function testSettingTreasuryAddressEvent() public {
        // only care that topic 1 matches
        vm.expectEmit(true, false, false, false);
        // event we expect
        emit TreasuryAddressChanged(RANDOM_ADDRESS);
        // event we get
        settings.setTreasury(RANDOM_ADDRESS);
    }

    function testFailSetSameTreasuryAddress() public {
        settings.setTreasury(KWENTA_TREASURY);
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
        settings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        settings.setTradeFee(1 ether);
    }

    function testFailSetSameTradeFee() public {
        settings.setTradeFee(tradeFee);
    }

    function testSettingTradeFeeEvent() public {
        // only care that topic 1 matches
        vm.expectEmit(true, false, false, false);
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
        settings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        settings.setLimitOrderFee(1 ether);
    }

    function testFailSetSameLimitOrderFee() public {
        settings.setTradeFee(limitOrderFee);
    }

    function testSettingLimitOrderFeeEvent() public {
        // only care that topic 1 matches
        vm.expectEmit(true, false, false, false);
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
        settings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        settings.setStopOrderFee(1 ether);
    }

    function testFailSetSameStopOrderFee() public {
        settings.setStopOrderFee(stopOrderFee);
    }

    function testSettingStopOrderFeeEvent() public {
        // only care that topic 1 matches
        vm.expectEmit(true, false, false, false);
        // event we expect
        emit StopOrderFeeChanged(stopOrderFee * 2);
        // event we get
        settings.setStopOrderFee(stopOrderFee * 2);
    }
}
