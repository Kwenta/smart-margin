// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../../src/Settings.sol";
import "../../src/interfaces/ISettings.sol";
import "../../src/Factory.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/Account.sol";
import "../../src/interfaces/IAccount.sol";

contract MarginAccountFactoryTest is Test {
    Settings settings;
    Factory factory;

    address constant addressResolver =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;
    address constant futuresManager =
        0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

    function mockAddressResolverCalls() internal {
        bytes32 futuresManagerKey = "FuturesMarketManager";
        vm.mockCall(
            address(addressResolver),
            abi.encodeWithSelector(
                IAddressResolver.requireAndGetAddress.selector,
                futuresManagerKey,
                "Account: Could not get Futures Market Manager"
            ),
            abi.encode(futuresManager)
        );
    }

    function setUp() public {
        mockAddressResolverCalls();

        // establish fees
        uint256 tradeFee = 5;
        uint256 limitOrderFee = 5;
        uint256 stopLossFee = 10;

        // deploy settings
        settings = new Settings({
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopLossFee
        });

        // deploy factory
        factory = new Factory({
            _owner: address(this),
            _version: "2.0.0",
            _marginAsset: address(0),
            _addressResolver: addressResolver,
            _settings: address(settings),
            _ops: payable(address(0))
        });
    }

    function testAccountCreation() public {
        address account = factory.newAccount();
        assertTrue(account != address(0));
        assertTrue(factory.creatorToAccount(address(this)) == address(account));
    }

    function testCannotCreateTwoAccounts() public {
        address account = factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.AlreadyCreatedAccount.selector,
                account
            )
        );
        factory.newAccount();
    }

    // Assert proxy is less than implementation
    function testAssertProxySize() public {
        address account = factory.newAccount();
        assertEq(account.code.length, 45); // 0age more minimal proxy is 45 bytes
        assertLt(
            account.code.length,
            address(factory.logic()).code.length
        );
    }

    function testAccountOwnerIsMsgSender() public {
        address payable account = factory.newAccount();
        assertEq(Account(account).owner(), address(this));
    }

    function testCannotInitAccountTwice() public {
        address payable account = factory.newAccount();
        vm.expectRevert();
        Account(account).initialize(
            address(0),
            address(0),
            address(0),
            payable(address(0))
        );
    }

    // @TODO testing...
}
