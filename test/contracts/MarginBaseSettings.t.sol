// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginBaseSettings.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";

contract MarginBaseSettingsTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MarginBaseSettings private marginBaseSettings;

    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;
    address private constant RANDOM_ADDRESS =
        0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    uint256 private tradeFee = 5; // 5 BPS
    uint256 private limitOrderFee = 5; // 5 BPS
    uint256 private stopOrderFee = 10; // 10 BPS

    // events
    event TreasuryAddressChanged(address treasury);
    event TradeFeeChanged(uint256 fee);
    event LimitOrderFeeChanged(uint256 fee);
    event StopOrderFeeChanged(uint256 fee);

    function setUp() public {
        marginBaseSettings = new MarginBaseSettings(
            KWENTA_TREASURY,
            tradeFee,
            limitOrderFee,
            stopOrderFee
        );
    }

    function testSettingsOwnerIsDeployer() public {
        assertEq(marginBaseSettings.owner(), address(this));
    }

    /**********************************
     * setTreasury
     **********************************/

    function testSettingTreasuryAddress() public {
        marginBaseSettings.setTreasury(RANDOM_ADDRESS);
        assertTrue(marginBaseSettings.treasury() == RANDOM_ADDRESS);
    }

    function testFailSettingTreasuryAddressIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setTreasury(RANDOM_ADDRESS);
    }

    function testShouldFailSettingTreasuryAddressToZero() public {
        cheats.expectRevert(
            abi.encodeWithSelector(MarginBaseSettings.ZeroAddress.selector)
        );
        marginBaseSettings.setTreasury(address(0));
    }

    function testSettingTreasuryAddressEvent() public {
        // only care that topic 1 matches
        cheats.expectEmit(true, false, false, false);
        // event we expect
        emit TreasuryAddressChanged(RANDOM_ADDRESS);
        // event we get
        marginBaseSettings.setTreasury(RANDOM_ADDRESS);
    }

    /**********************************
     * Set Distribution Fee
     **********************************/

    /// @dev fuzz test
    function testSettingTradeFee(uint256 x) public {
        if (x == marginBaseSettings.tradeFee()) {
            cheats.expectRevert(
                abi.encodeWithSelector(MarginBaseSettings.DuplicateFee.selector)
            );
            marginBaseSettings.setTradeFee(x);
            return;
        }
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidFee.selector,
                    x
                )
            );
            marginBaseSettings.setTradeFee(x);
            return;
        }
        marginBaseSettings.setTradeFee(x);
        assertTrue(marginBaseSettings.tradeFee() == x);
    }

    function testFailSetTradeFeeIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setTradeFee(1 ether);
    }

    function testFailSetSameTradeFee() public {
        marginBaseSettings.setTradeFee(tradeFee);
    }

    function testSettingTradeFeeEvent() public {
        // only care that topic 1 matches
        cheats.expectEmit(true, false, false, false);
        // event we expect
        emit TradeFeeChanged(tradeFee * 2);
        // event we get
        marginBaseSettings.setTradeFee(tradeFee * 2);
    }

    /**********************************
     * Set Limit Order Fee
     **********************************/

    /// @dev fuzz test
    function testSettingLimitOrderFee(uint256 x) public {
        if (x == marginBaseSettings.limitOrderFee()) {
            cheats.expectRevert(
                abi.encodeWithSelector(MarginBaseSettings.DuplicateFee.selector)
            );
            marginBaseSettings.setTradeFee(x);
            return;
        }
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidFee.selector,
                    x
                )
            );
            marginBaseSettings.setLimitOrderFee(x);
            return;
        }
        marginBaseSettings.setLimitOrderFee(x);
        assertTrue(marginBaseSettings.limitOrderFee() == x);
    }

    function testFailSetLimitOrderFeeIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setLimitOrderFee(1 ether);
    }

    function testFailSetSameLimitOrderFee() public {
        marginBaseSettings.setTradeFee(limitOrderFee);
    }

    function testSettingLimitOrderFeeEvent() public {
        // only care that topic 1 matches
        cheats.expectEmit(true, false, false, false);
        // event we expect
        emit LimitOrderFeeChanged(limitOrderFee * 2);
        // event we get
        marginBaseSettings.setLimitOrderFee(limitOrderFee * 2);
    }

    /**********************************
     * Set Stop Loss Fee
     **********************************/

    /// @dev fuzz test
    function testSettingStopOrderFee(uint256 x) public {
        if (x == marginBaseSettings.stopOrderFee()) {
            cheats.expectRevert(
                abi.encodeWithSelector(MarginBaseSettings.DuplicateFee.selector)
            );
            marginBaseSettings.setTradeFee(x);
            return;
        }
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidFee.selector,
                    x
                )
            );
            marginBaseSettings.setStopOrderFee(x);
            return;
        }
        marginBaseSettings.setStopOrderFee(x);
        assertTrue(marginBaseSettings.stopOrderFee() == x);
    }

    function testFailSetStopOrderFeeIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setStopOrderFee(1 ether);
    }

    function testFailSetSameStopOrderFee() public {
        marginBaseSettings.setStopOrderFee(stopOrderFee);
    }

    function testSettingStopOrderFeeEvent() public {
        // only care that topic 1 matches
        cheats.expectEmit(true, false, false, false);
        // event we expect
        emit StopOrderFeeChanged(stopOrderFee * 2);
        // event we get
        marginBaseSettings.setStopOrderFee(stopOrderFee * 2);
    }
}
