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

    function setUp() public {
        /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
        uint256 distributionFee = 5; // 5 BPS
        marginBaseSettings = new MarginBaseSettings(distributionFee);
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
        marginBaseSettings.transferOwnership(0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B); // not a zero address
        marginBaseSettings.setDistributionFee(x);
    }
}
