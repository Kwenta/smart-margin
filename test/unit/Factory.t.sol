// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {MockAccount1, MockAccount2} from "../utils/MockAccounts.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import {UpgradedAccount} from "../utils/UpgradedAccount.sol";
import "../utils/Constants.sol";

contract FactoryTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Events private events;
    Factory private factory;
    Account private implementation;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            isMainnet: false,
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: TRADE_FEE,
            limitOrderFee: LIMIT_ORDER_FEE,
            stopOrderFee: STOP_ORDER_FEE,
            addressResolver: ADDRESS_RESOLVER,
            marginAsset: MARGIN_ASSET,
            gelato: GELATO,
            ops: OPS
        });
        settings = Settings(factory.settings());
        events = Events(factory.events());
        implementation = Account(payable(factory.implementation()));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Owner() public {
        assertEq(factory.owner(), address(this));
    }

    function test_Constructor_Settings() public {
        assertEq(address(factory.settings()), address(settings));
    }

    function test_Constructor_Events() public {
        assertEq(address(factory.events()), address(events));
    }

    function test_Constructor_Implementation() public {
        assertEq(factory.implementation(), address(implementation));
    }

    function test_Constructor_CanUpgrade() public {
        assertEq(factory.canUpgrade(), true);
    }

    function test_Constructor_Accounts(address fuzzedAddress) public view {
        assert(!factory.accounts(fuzzedAddress));
    }

    /*//////////////////////////////////////////////////////////////
                           FACTORY OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_Ownership_Transfer() public {
        factory.transferOwnership(USER);
        assertEq(factory.owner(), USER);
    }

    function test_Ownership_NonAccount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.AccountDoesNotExist.selector)
        );
        factory.getAccountOwner(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_UpdateAccountOwnership_OldOwner_SingleAccount() public {
        address payable accountAddress = factory.newAccount();
        Account(accountAddress).transferOwnership(USER);

        // check `ownerAccounts` mapping updated
        assertEq(factory.getAccountsOwnedBy(USER).length, 1);
        assertEq(factory.getAccountsOwnedBy(USER)[0], accountAddress);
        assertEq(factory.getAccountsOwnedBy(address(this)).length, 0);

        // check owner changed
        assertEq(factory.getAccountOwner(accountAddress), USER);
    }

    function test_UpdateAccountOwnership_OldOwner_MultipleAccount(uint256 x)
        public
    {
        vm.assume(x < 10); // avoid running out of gas

        uint256 y = x;
        while (y > 0) {
            factory.newAccount();
            y--;
        }

        address payable accountAddress = factory.newAccount();
        Account(accountAddress).transferOwnership(USER);

        // check `ownerAccounts` mapping updated
        assertEq(factory.getAccountsOwnedBy(USER).length, 1);
        assertEq(factory.getAccountsOwnedBy(USER)[0], accountAddress);
        assertEq(factory.getAccountsOwnedBy(address(this)).length, x);

        // check owner changed
        assertEq(factory.getAccountOwner(accountAddress), USER);
    }

    function test_UpdateAccountOwnership_NewOwner_MultipleAccount(uint256 x)
        public
    {
        vm.assume(x < 10); // avoid running out of gas

        address payable accountAddress;

        uint256 y = x;
        while (y > 0) {
            accountAddress = factory.newAccount();
            Account(accountAddress).transferOwnership(USER);

            // check `ownerAccounts` mapping updated
            assertEq(factory.getAccountsOwnedBy(USER)[x - y], accountAddress);

            // check owner changed
            assertEq(factory.getAccountOwner(accountAddress), USER);
            y--;
        }

        // check `ownerAccounts` mapping updated
        assertEq(factory.getAccountsOwnedBy(USER).length, x);
        assertEq(factory.getAccountsOwnedBy(address(this)).length, 0);
    }

    function test_UpdateAccountOwnership_OnlyAccount() public {
        address payable accountAddress = factory.newAccount();
        vm.expectRevert(abi.encodeWithSelector(IFactory.OnlyAccount.selector));
        factory.updateAccountOwnership(accountAddress, USER, address(this));
    }

    function test_UpdateAccountOwnership_AccountDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.AccountDoesNotExist.selector)
        );
        factory.updateAccountOwnership(address(0xCAFEBAE), USER, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_NewAccount_Address() public {
        address payable accountAddress = factory.newAccount();
        assert(accountAddress != address(0));
    }

    function test_NewAccount_Event() public {
        vm.expectEmit(true, false, false, false);
        emit NewAccount(address(this), address(0), bytes32(0));
        factory.newAccount();
    }

    function test_NewAccount_State() public {
        address payable accountAddress = factory.newAccount();
        assert(factory.accounts(accountAddress));
    }

    function test_NewAccount_MultiplePerAddress() public {
        address payable accountAddress1 = factory.newAccount();
        assert(factory.accounts(accountAddress1));
        address payable accountAddress2 = factory.newAccount();
        assert(factory.accounts(accountAddress2));
        assertEq(
            factory.getAccountOwner(accountAddress1),
            factory.getAccountOwner(accountAddress2)
        );
    }

    /// @dev this error does not catch 100% of scenarios.
    /// it is possible for an implementation to lack an
    /// initialize() function but contain a fallback()
    /// function and AccountFailedToInitialize error
    /// would *NOT* be triggered.
    ///
    /// Given this, it is up to the factory owner to take
    /// extra care when creating the implementation to be used
    function test_NewAccount_CannotBeInitialized() public {
        MockAccount1 mockAccount = new MockAccount1();
        factory = new Factory({
            _owner: address(this),
            _settings: address(settings),
            _events: address(events),
            _implementation: address(mockAccount)
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.AccountFailedToInitialize.selector, ""
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
    function test_NewAccount_CannotFetchVersion() public {
        MockAccount2 mockAccount = new MockAccount2();
        factory = new Factory({
            _owner: address(this),
            _settings: address(settings),
            _events: address(events),
            _implementation: address(mockAccount)
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IFactory.AccountFailedToFetchVersion.selector, ""
            )
        );
        factory.newAccount();
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                          REMOVE UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_Remove_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(ACCOUNT);
        factory.removeUpgradability();
    }

    function test_Upgrade_Remove() public {
        factory.removeUpgradability();
        assertEq(factory.canUpgrade(), false);
    }

    /*//////////////////////////////////////////////////////////////
                             IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_Implementation_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(ACCOUNT);
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function test_Upgrade_Implementation() public {
        address payable accountAddress = factory.newAccount();
        UpgradedAccount newImplementation = new UpgradedAccount();
        factory.upgradeAccountImplementation({
            _implementation: address(newImplementation)
        });
        // check version changed
        bytes32 newVersion = "6.9.0";
        assertEq(Account(accountAddress).VERSION(), newVersion);
        // check owner did not change
        assertEq(Account(accountAddress).owner(), address(this));
        // check new account uses new implementation
        vm.prank(ACCOUNT);
        address payable accountAddress2 = factory.newAccount();
        assertEq(Account(accountAddress2).VERSION(), newVersion);
        assertEq(Account(accountAddress2).owner(), ACCOUNT);
    }

    function test_Upgrade_Implementation_Event() public {
        vm.expectEmit(true, true, true, true);
        emit AccountImplementationUpgraded(address(0));
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function test_Upgrade_Implementation_UpgradabilityRemoved() public {
        factory.removeUpgradability();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CannotUpgrade.selector));
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    /*//////////////////////////////////////////////////////////////
                                SETTINGS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_Settings_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(KWENTA_TREASURY);
        factory.upgradeSettings({_settings: address(0)});
    }

    function test_Upgrade_Settings() public {
        address payable accountAddress = factory.newAccount();
        address newSettings = address(
            new Settings({
                _owner: ACCOUNT, // this upgrade changes owner
                _treasury: KWENTA_TREASURY,
                _tradeFee: TRADE_FEE,
                _limitOrderFee: LIMIT_ORDER_FEE,
                _stopOrderFee: STOP_ORDER_FEE
            })
        );
        factory.upgradeSettings({_settings: newSettings});
        // check settings owner did *NOT* change
        assertEq(
            Settings(address(Account(accountAddress).settings())).owner(),
            address(this)
        );
        // check new account uses new settings
        address payable accountAddress2 = factory.newAccount();
        // check new accounts settings owner did change
        assertEq(
            Settings(address(Account(accountAddress2).settings())).owner(),
            ACCOUNT
        );
    }

    function test_Upgrade_Settings_Event() public {
        vm.expectEmit(true, true, true, true);
        emit SettingsUpgraded(address(0));
        factory.upgradeSettings({_settings: address(0)});
    }

    function test_Upgrade_Settings_UpgradabilityRemoved() public {
        factory.removeUpgradability();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CannotUpgrade.selector));
        factory.upgradeSettings({_settings: address(0)});
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_Events_OnlyOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(KWENTA_TREASURY);
        factory.upgradeEvents({_events: address(0)});
    }

    function test_Upgrade_Events() public {
        address payable accountAddress = factory.newAccount();
        factory.upgradeEvents({_events: address(0)});
        // check upgrade did not impact previously deployed account
        assert(address(Account(accountAddress).events()) != address(0));
        // check new account uses new events
        address payable accountAddress2 = factory.newAccount();
        assert(address(Account(accountAddress2).events()) == address(0));
    }

    function test_Upgrade_Events_Event() public {
        vm.expectEmit(true, true, true, true);
        emit EventsUpgraded(address(0));
        factory.upgradeEvents({_events: address(0)});
    }

    function test_Upgrade_Events_UpgradabilityRemoved() public {
        factory.removeUpgradability();
        vm.expectRevert(abi.encodeWithSelector(IFactory.CannotUpgrade.selector));
        factory.upgradeEvents({_events: address(0)});
    }
}
