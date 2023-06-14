// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "lib/forge-std/src/Test.sol";
import "../utils/Constants.sol";
import {AccountProxy} from "../../src/AccountProxy.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {IAccountProxy} from "../../src/interfaces/IAccountProxy.sol";

contract AccountProxyTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    AccountProxy private accountProxy;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        accountProxy = new AccountProxy(BEACON);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
}
