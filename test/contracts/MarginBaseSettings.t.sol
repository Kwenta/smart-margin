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

    function setUp() public {
        /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
        uint256 tradeFee = 5; // 5 BPS
        uint256 limitOrderFee = 5; // 5 BPS
        uint256 stopOrderFee = 10; // 10 BPS
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

    // @TODO: test events

    /**********************************
     * Set Distribution Fee
     **********************************/

    /// @dev fuzz test
    function testSettingTradeFee(uint256 x) public {
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

    // @TODO: test events

    /**********************************
     * Set Limit Order Fee
     **********************************/

    /// @dev fuzz test
    function testSettingLimitOrderFee(uint256 x) public {
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

    // @TODO: test events

    /**********************************
     * Set Stop Loss Fee
     **********************************/

    /// @dev fuzz test
    function testSettingStopOrderFee(uint256 x) public {
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

    // @TODO: test events
}
