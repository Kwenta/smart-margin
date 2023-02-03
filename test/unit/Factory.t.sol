// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Settings} from "../../src/Settings.sol";
import {ISettings} from "../../src/interfaces/ISettings.sol";
import {Factory} from "../../src/Factory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {Account} from "../../src/Account.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {AccountProxy} from "../../src/AccountProxy.sol";
import {IAccountProxy} from "../../src/interfaces/IAccountProxy.sol";
import {MockAccount1, MockAccount2} from "./utils/MockAccounts.sol";
import {UpgradedAccount} from "./utils/UpgradedAccount.sol";

contract FactoryTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    Settings private settings;
    Factory private factory;
    Account private implementation;

    address private constant TEST_ACCOUNT =
        0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c;
    address private constant ADDRESS_RESOLVER =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address private constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address private constant GELATO_OPS =
        0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;
    address private constant FUTURES_MANAGER =
        0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

    uint256 private constant TRADE_FEE = 5;
    uint256 private constant LIMIT_ORDER_FEE = 5;
    uint256 private constant STOP_LOSS_FEE = 10;

    event NewAccount(
        address indexed creator,
        address indexed account,
        bytes32 version
    );
    event AccountImplementationUpgraded(address implementation);
    event SettingsUpgraded(address settings);
    event MarginAssetUpgraded(address marginAsset);
    event AddressResolverUpgraded(address addressResolver);
    event OpsUpgraded(address payable ops);

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_LOSS_FEE
        });

        implementation = new Account();

        factory = new Factory({
            _owner: address(this),
            _marginAsset: SUSD,
            _addressResolver: ADDRESS_RESOLVER,
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
            _implementation: address(implementation)
        });
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testOwnerSet() public {
        assertEq(factory.owner(), address(this));
    }

    function testCanUpgrade() public {
        assertEq(factory.canUpgrade(), true);
    }

    function testImplementationSet() public {
        assertEq(factory.implementation(), address(implementation));
    }

    function testSettingsSet() public {
        assertEq(address(factory.settings()), address(settings));
    }

    function testMarginAssetSet() public {
        assertEq(address(factory.marginAsset()), SUSD);
    }

    function testAddressResolverSet() public {
        assertEq(address(factory.addressResolver()), ADDRESS_RESOLVER);
    }

    function testGelatoOpsSet() public {
        assertEq(factory.ops(), GELATO_OPS);
    }

    /*//////////////////////////////////////////////////////////////
                           FACTORY OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testCanTransferOwnership() public {
        factory.transferOwnership(address(0xCAFEBAE));
        assertEq(factory.owner(), address(0xCAFEBAE));
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function testNewAccount() public {
        address payable accountAddress = factory.newAccount();
        assert(accountAddress != address(0));
    }

    function testAccountAddedToMapping() public {
        address payable accountAddress = factory.newAccount();
        assertEq(factory.ownerToAccount(address(this)), accountAddress);
    }

    function testCannotCreateTwoAccounts() public {
        address payable accountAddress = factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.OnlyOneAccountPerAddress.selector,
                accountAddress
            )
        );
        factory.newAccount();
    }

    /// @dev this error does not catch 100% of scenarios.
    /// it is possible for an implementation to lack an
    /// initialize() function but contain a fallback()
    /// function and AccountFailedToInitialize error
    /// would *NOT* be triggered.
    ///
    /// Given this, it is up to the factory owner to take
    /// extra care when creating the implementation to be used
    function testWhenAccountCannotBeInitialized() public {
        MockAccount1 mockAccount = new MockAccount1();

        factory = new Factory({
            _owner: address(this),
            _marginAsset: SUSD,
            _addressResolver: ADDRESS_RESOLVER,
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
            _implementation: address(mockAccount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.AccountFailedToInitialize.selector,
                ""
            )
        );
        factory.newAccount();
    }

    /// @dev this error does not catch 100% of scenarios.
    /// it is possible for an implementation to lack a
    /// VERSION() function but contain a fallback()
    /// function and AccountFailedToFetchVersion error
    /// would *NOT* be triggered.
    ///
    /// Given this, it is up to the factory owner to take
    /// extra care when creating the implementation to be used
    function testWhenAccountCannotFetchVersion() public {
        MockAccount2 mockAccount = new MockAccount2();

        factory = new Factory({
            _owner: address(this),
            _marginAsset: SUSD,
            _addressResolver: ADDRESS_RESOLVER,
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
            _implementation: address(mockAccount)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.AccountFailedToFetchVersion.selector,
                ""
            )
        );
        factory.newAccount();
    }

    function testNewAccountEvent() public {
        vm.expectEmit(true, false, false, false);
        emit NewAccount(address(this), address(0), bytes32(0));
        factory.newAccount();
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testAccountCanTransferAccountOwnership() public {
        address payable accountAddress = factory.newAccount();
        Account(accountAddress).transferOwnership({
            _newOwner: address(0xCAFEBAE)
        });
        assertEq(factory.ownerToAccount(address(this)), address(0));
        assertEq(factory.ownerToAccount(address(0xCAFEBAE)), accountAddress);
        assertEq(Account(accountAddress).owner(), address(0xCAFEBAE));
    }

    function testAccountCannotTransferOwnershipToAnotherAccountOwningAddress()
        public
    {
        address payable accountAddress1 = factory.newAccount();
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.OnlyOneAccountPerAddress.selector,
                accountAddress2
            )
        );
        Account(accountAddress1).transferOwnership({_newOwner: TEST_ACCOUNT});
    }

    function testAccountOwnerCannotTransferAnotherAccount() public {
        factory.newAccount();
        vm.prank(TEST_ACCOUNT);
        factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CallerMustBeAccount.selector)
        );
        // try to brick account owned by TEST_ACCOUNT
        factory.updateAccountOwner({
            _oldOwner: TEST_ACCOUNT,
            _newOwner: address(0)
        });
    }

    function testCannotUpdateAccountThatDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.AccountDoesNotExist.selector)
        );
        factory.updateAccountOwner({
            _oldOwner: address(0xCAFEBAE),
            _newOwner: address(0xBEEF)
        });
    }

    function testCannotDirectlyUpdateAccount() public {
        factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CallerMustBeAccount.selector)
        );
        factory.updateAccountOwner({
            _oldOwner: address(this),
            _newOwner: address(0xBEEF)
        });
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    function testCannotUpgradeAccountImplementationWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(TEST_ACCOUNT);
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function testUpgradeAccountImplementation() public {
        address payable accountAddress = factory.newAccount();
        UpgradedAccount newImplementation = new UpgradedAccount();
        factory.upgradeAccountImplementation({
            _implementation: address(newImplementation)
        });
        // check version changed
        bytes32 newVersion = "2.0.1";
        assertEq(Account(accountAddress).VERSION(), newVersion);
        // check owner did not change
        assertEq(Account(accountAddress).owner(), address(this));
        // check new account uses new implementation
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        assertEq(Account(accountAddress2).VERSION(), newVersion);
        assertEq(Account(accountAddress2).owner(), TEST_ACCOUNT);
    }

    function testUpgradeAccountImplementationEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AccountImplementationUpgraded(address(0));
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function testCannotUpgradeSettingsWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(KWENTA_TREASURY);
        factory.upgradeSettings({_settings: address(0)});
    }

    function testUpgradeSettings() public {
        address payable accountAddress = factory.newAccount();
        address newSettings = address(
            new Settings({
                _owner: TEST_ACCOUNT, // change owner
                _treasury: KWENTA_TREASURY,
                _tradeFee: TRADE_FEE,
                _limitOrderFee: LIMIT_ORDER_FEE,
                _stopOrderFee: STOP_LOSS_FEE
            })
        );
        factory.upgradeSettings({_settings: newSettings});
        // check settings owner did *NOT* change
        assertEq(
            Settings(address(Account(accountAddress).settings())).owner(),
            address(this)
        );
        // check new account uses new settings
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        // check new accounts settings owner did change
        assertEq(
            Settings(address(Account(accountAddress2).settings())).owner(),
            TEST_ACCOUNT
        );
    }

    function testUpgradeSettingsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SettingsUpgraded(address(0));
        factory.upgradeSettings({_settings: address(0)});
    }

    function testCannotUpgradeMarginAssetWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(TEST_ACCOUNT);
        factory.upgradeMarginAsset({_marginAsset: address(0)});
    }

    function testUpgradeMarginAsset() public {
        address payable accountAddress = factory.newAccount();
        factory.upgradeMarginAsset({_marginAsset: address(0)});
        // check margin asset address did *NOT* change
        assertEq(address(Account(accountAddress).marginAsset()), SUSD);
        // check new account uses new margin asset
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        // check margin asset address did change
        assertEq(address(Account(accountAddress2).marginAsset()), address(0));
    }

    function testUpgradeMarginAssetEvent() public {
        vm.expectEmit(true, true, true, true);
        emit MarginAssetUpgraded(address(0));
        factory.upgradeMarginAsset({_marginAsset: address(0)});
    }

    function testCannotUpgradeAddressResolverWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(TEST_ACCOUNT);
        factory.upgradeAddressResolver({_addressResolver: address(0)});
    }

    function testUpgradeAddressResolver() public {
        address payable accountAddress = factory.newAccount();
        factory.upgradeAddressResolver({_addressResolver: address(0)});
        // check address resolver address did *NOT* change
        assertEq(
            address(Account(accountAddress).addressResolver()),
            ADDRESS_RESOLVER
        );
        // check new account uses new address resolver
        vm.prank(TEST_ACCOUNT);
        vm.expectRevert(); // revert from invalid address resolver
        factory.newAccount();
    }

    function testUpgradeAddressResolverEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AddressResolverUpgraded(address(0));
        factory.upgradeAddressResolver({_addressResolver: address(0)});
    }

    function testCannotUpgradeOpsWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(TEST_ACCOUNT);
        factory.upgradeOps({_ops: payable(address(0))});
    }

    function testUpgradeOps() public {
        address payable accountAddress = factory.newAccount();
        factory.upgradeOps({_ops: payable(address(0))});
        // check ops address did *NOT* change
        assertEq(address(Account(accountAddress).ops()), GELATO_OPS);
        // check new account uses new ops
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        // check ops address did change
        assertEq(address(Account(accountAddress2).ops()), address(0));
    }

    function testUpgradeOpsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit OpsUpgraded(payable(address(0)));
        factory.upgradeOps({_ops: payable(address(0))});
    }

    function testCannotRemoveUpgradabilityWhenNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(TEST_ACCOUNT);
        factory.removeUpgradability();
    }

    function testCanRemoveUpgradability() public {
        factory.removeUpgradability();
        assertEq(factory.canUpgrade(), false);
    }

    function testCannotUpgradeAccountImplementationWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CannotUpgrade.selector)
        );
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function testCannotUpgradeSettingsWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CannotUpgrade.selector)
        );
        factory.upgradeSettings({_settings: address(0)});
    }

    function testCannotUpgradeMarginAssetWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CannotUpgrade.selector)
        );
        factory.upgradeMarginAsset({_marginAsset: address(0)});
    }

    function testCannotUpgradeAddressResolverWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CannotUpgrade.selector)
        );
        factory.upgradeAddressResolver({_addressResolver: address(0)});
    }

    function testCannotOpsWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.CannotUpgrade.selector)
        );
        factory.upgradeOps({_ops: payable(address(0))});
    }
}
