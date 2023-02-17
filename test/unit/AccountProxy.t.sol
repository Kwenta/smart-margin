// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {IAccountProxy} from "../../src/interfaces/IAccountProxy.sol";
import {AccountProxy} from "../../src/AccountProxy.sol";

contract AccountProxyTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    AccountProxy private accountProxy;

    address private constant BEACON = address(0xA);

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        accountProxy = new AccountProxy(BEACON);
    }

    // @TODO
}
