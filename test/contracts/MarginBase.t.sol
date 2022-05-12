// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "./utils/MintableERC20.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 marginAsset;
    MarginAccountFactory marginAccountFactory;
    MarginBase account;

    function setUp() public {
        marginAsset = new MintableERC20(address(this), 0);
        marginAccountFactory = new MarginAccountFactory("0.0.0", address(marginAsset));
        account = MarginBase(marginAccountFactory.newAccount());
    }

    function testOwnership() public {
        assertEq(account.owner(), address(this));
    }

    function testExpectedMargin() public {
        assertEq(address(account.margin()), address(marginAsset));
    }

    function testDeposit() public {
        uint amount = 10e18;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        assertEq(marginAsset.balanceOf(address(account)), amount);
    }

    function testWithdrawal() public {
        uint amount = 10e18;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint amount) public {
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }
}