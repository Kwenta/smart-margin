// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "./utils/MintableERC20.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 private marginAsset;
    MarginAccountFactory private marginAccountFactory;
    MarginBase private account;

    // works for fork testing
    address private addressResolver = 0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C;

    function setUp() public {
        marginAsset = new MintableERC20(address(this), 0);
        marginAccountFactory = new MarginAccountFactory("0.0.0", address(marginAsset), addressResolver, payable(address(0)));
        account = MarginBase(marginAccountFactory.newAccount());
    }

    function testOwnership() public {
        assertEq(account.owner(), address(this));
    }

    function testExpectedMargin() public {
        assertEq(address(account.marginAsset()), address(marginAsset));
    }

    function deposit(uint amount) internal {
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
    }

    function testDeposit() public {
        uint amount = 10e18;
        deposit(amount);
        assertEq(marginAsset.balanceOf(address(account)), amount);
    }

    function testWithdrawal() public {
        uint amount = 10e18;
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint amount) public {
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    function testPlaceOrder() public {
        uint amount = 10e18;
        uint currentPrice = 2e18;
        uint limitPrice = 3e18;
        deposit(amount);
        account.placeOrder(address(0), 1e18, 1e18, 1e18);
        cheats.mockCall(account.gelato(), "nil", abi.encode(true));
    }
}