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
        uint256 distributionFee = 5; // 5 BPS
        uint256 limitOrderFee = 5; // 5 BPS
        uint256 stopLossFee = 10; // 10 BPS
        marginBaseSettings = new MarginBaseSettings(
            KWENTA_TREASURY,
            distributionFee,
            limitOrderFee,
            stopLossFee
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

    /**********************************
     * Set Distribution Fee
     **********************************/

    /// @dev fuzz test
    function testSettingDistributionFee(uint256 x) public {
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidDistributionFee.selector,
                    x
                )
            );
            marginBaseSettings.setDistributionFee(x);
            return;
        }
        marginBaseSettings.setDistributionFee(x);
        assertTrue(marginBaseSettings.distributionFee() == x);
    }

    function testFailSetDistributionFeeIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setDistributionFee(1 ether);
    }

    /**********************************
     * Set Limit Order Fee
     **********************************/

    /// @dev fuzz test
    function testSettingLimitOrderFee(uint256 x) public {
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidLimitOrderFee.selector,
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

    /**********************************
     * Set Stop Loss Fee
     **********************************/

    /// @dev fuzz test
    function testSettingStopLossFee(uint256 x) public {
        if (x >= 10_000) {
            cheats.expectRevert(
                abi.encodeWithSelector(
                    MarginBaseSettings.InvalidStopLossFee.selector,
                    x
                )
            );
            marginBaseSettings.setStopLossFee(x);
            return;
        }
        marginBaseSettings.setStopLossFee(x);
        assertTrue(marginBaseSettings.stopLossFee() == x);
    }

    function testFailSetStopLossFeeIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setStopLossFee(1 ether);
    }
}
