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

    /// @dev fuzz test
    function testSettingDistributionFee(uint256 x) public {
        cheats.assume(x < 10_000);
        marginBaseSettings.setDistributionFee(x);
        assertTrue(marginBaseSettings.distributionFee() == x);
    }

    function testFailSetDistributionFeeIfNotOwner(uint256 x) public {
        cheats.assume(x < 10_000);
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setDistributionFee(x);
    }

    function testSettingTreasuryAddress() public {
        marginBaseSettings.setTreasury(RANDOM_ADDRESS);
        assertTrue(marginBaseSettings.treasury() == RANDOM_ADDRESS);
    }

    function testFailSettingTreasuryAddressIfNotOwner() public {
        marginBaseSettings.transferOwnership(RANDOM_ADDRESS); // not a zero address
        marginBaseSettings.setTreasury(RANDOM_ADDRESS);
    }

    // @TODO fuzz test other fees
}
