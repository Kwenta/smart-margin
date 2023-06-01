// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../utils/Constants.sol";
import "../../../script/utils/parameters/OptimismGoerliParameters.sol";
import {UpgradeAccountOptimismGoerli} from
    "../../../script/upgrades/v2.0.2/Upgrade.s.sol";
import {Account} from "../../../src/Account.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../../src/Events.sol";
import {Factory} from "../../../src/Factory.sol";
import {IAccount} from "../../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../../utils/interfaces/IAddressResolver.sol";
import {ISynth} from "../../utils/interfaces/ISynth.sol";
import {Settings} from "../../../src/Settings.sol";

contract UpgradeTest is Test {
    // BLOCK_NUMBER corresponds to Optimism Goerli network state @ Jun-01-2023 08:24:34 PM +UTC
    // hard coded addresses are only guaranteed for this block
    uint256 constant BLOCK_NUMBER_UPGRADE = 10_111_503;

    /*//////////////////////////////////////////////////////////////
                         V2.0.1 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    address private constant OLD_IMPLEMENTATION =
        0x76210dbA7b06bC40ec4E152D2Dcfd6bFa8102a8a;

    /*//////////////////////////////////////////////////////////////
                         V2.0.2 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    Account private NEW_IMPLEMENTATION;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev account only active at the specified block number
    address ACTIVE_ACCOUNT = 0x043e7c673F2bd9c62e69921395bfd1f97ACc0A78;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER_UPGRADE);

        // define Setup contract used for upgrades
        UpgradeAccountOptimismGoerli upgradeAccountOptimismGoerli =
            new UpgradeAccountOptimismGoerli();

        // deploy v2.0.2 implementation
        address implementationAddr = upgradeAccountOptimismGoerli.upgrade();
        NEW_IMPLEMENTATION = Account(payable(implementationAddr));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployed_Account_Version() public {
        (, bytes memory response) = OLD_IMPLEMENTATION.call(
            abi.encodeWithSelector(IAccount.VERSION.selector)
        );
        (bytes32 version) = abi.decode(response, (bytes32));
        assertEq(version, "2.0.1", "wrong version");
    }

    function test_Upgrade() public {}
}
