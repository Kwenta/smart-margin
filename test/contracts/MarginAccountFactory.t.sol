// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    MarginAccountFactory marginAccountFactory;

    function setUp() public {
        marginAccountFactory = new MarginAccountFactory("0.0.0", address(0));
    }

    function testAccountCreation() public {
        address account = marginAccountFactory.newAccount();
        assertTrue(account != address(0));
    }

    // Assert proxy is less than implementation
    function testAssertProxySize() public {
        address account = marginAccountFactory.newAccount();
        assertEq(account.code.length, 45); // Minimal proxy is 45 bytes
        assertLt(account.code.length, address(marginAccountFactory.implementation()).code.length);
    }

    function testAccountOwnerIsMsgSender() public {
        MarginBase account = MarginBase(marginAccountFactory.newAccount());
        assertEq(account.owner(), address(this));
    }
}