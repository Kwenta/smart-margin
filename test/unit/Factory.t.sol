// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {ISettings} from "../../src/interfaces/ISettings.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {MockAccount1, MockAccount2} from "./utils/MockAccounts.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import {UpgradedAccount} from "./utils/UpgradedAccount.sol";

contract FactoryTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    Settings private settings;
    Events private events;
    Factory private factory;
    Account private implementation;

    address private constant TEST_ACCOUNT = 0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c;
    address private constant KWENTA_TREASURY = 0x82d2242257115351899894eF384f779b5ba8c695;
    address private constant FUTURES_MANAGER = 0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

    uint256 private tradeFee = 1;
    uint256 private limitOrderFee = 2;
    uint256 private stopOrderFee = 3;

    event NewAccount(address indexed creator, address indexed account, bytes32 version);
    event AccountImplementationUpgraded(address implementation);
    event SettingsUpgraded(address settings);

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // uses deployment script for tests (2 birds 1 stone)
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: tradeFee,
            limitOrderFee: limitOrderFee,
            stopOrderFee: stopOrderFee
        });

        settings = Settings(factory.settings());
        events = Events(factory.events());
        implementation = Account(payable(factory.implementation()));
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
            abi.encodeWithSelector(IFactory.OnlyOneAccountPerAddress.selector, accountAddress)
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
            _settings: address(settings),
            _events: address(events),
            _implementation: address(mockAccount)
        });

        vm.expectRevert(abi.encodeWithSelector(IFactory.AccountFailedToInitialize.selector, ""));
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
            _settings: address(settings),
            _events: address(events),
            _implementation: address(mockAccount)
        });

        vm.expectRevert(abi.encodeWithSelector(IFactory.AccountFailedToFetchVersion.selector, ""));
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
        Account(accountAddress).transferOwnership({_newOwner: address(0xCAFEBAE)});
        assertEq(factory.ownerToAccount(address(this)), address(0));
        assertEq(factory.ownerToAccount(address(0xCAFEBAE)), accountAddress);
        assertEq(Account(accountAddress).owner(), address(0xCAFEBAE));
    }

    function testAccountCannotTransferOwnershipToAnotherAccountOwningAddress() public {
        address payable accountAddress1 = factory.newAccount();
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.OnlyOneAccountPerAddress.selector, accountAddress2)
        );
        Account(accountAddress1).transferOwnership({_newOwner: TEST_ACCOUNT});
    }

    function testAccountOwnerCannotTransferAnotherAccount() public {
        factory.newAccount();
        vm.prank(TEST_ACCOUNT);
        factory.newAccount();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CallerMustBeAccount.selector));
        // try to brick account owned by TEST_ACCOUNT
        factory.updateAccountOwner({_oldOwner: TEST_ACCOUNT, _newOwner: address(0)});
    }

    function testCannotUpdateAccountThatDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(IFactory.AccountDoesNotExist.selector));
        factory.updateAccountOwner({_oldOwner: address(0xCAFEBAE), _newOwner: address(0xBEEF)});
    }

    function testCannotDirectlyUpdateAccount() public {
        factory.newAccount();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CallerMustBeAccount.selector));
        factory.updateAccountOwner({_oldOwner: address(this), _newOwner: address(0xBEEF)});
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
        factory.upgradeAccountImplementation({_implementation: address(newImplementation)});
        // check version changed
        bytes32 newVersion = "6.9.0";
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
                _tradeFee: tradeFee,
                _limitOrderFee: limitOrderFee,
                _stopOrderFee: stopOrderFee
            })
        );
        factory.upgradeSettings({_settings: newSettings});
        // check settings owner did *NOT* change
        assertEq(Settings(address(Account(accountAddress).settings())).owner(), address(this));
        // check new account uses new settings
        vm.prank(TEST_ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        // check new accounts settings owner did change
        assertEq(Settings(address(Account(accountAddress2).settings())).owner(), TEST_ACCOUNT);
    }

    function testUpgradeSettingsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SettingsUpgraded(address(0));
        factory.upgradeSettings({_settings: address(0)});
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
        vm.expectRevert(abi.encodeWithSelector(IFactory.CannotUpgrade.selector));
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function testCannotUpgradeSettingsWhenNotEnabled() public {
        factory.removeUpgradability();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CannotUpgrade.selector));
        factory.upgradeSettings({_settings: address(0)});
    }
}
