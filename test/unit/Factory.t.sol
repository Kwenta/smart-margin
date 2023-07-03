// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Factory} from "../../src/Factory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {MockAccount1} from "../utils/MockAccounts.sol";
import {MockAccount2} from "../utils/MockAccounts.sol";
import {Setup} from "../../script/Deploy.s.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {UpgradedAccount} from "../utils/UpgradedAccount.sol";
import {
    ADDRESS_RESOLVER,
    BLOCK_NUMBER,
    GELATO,
    KWENTA_TREASURY,
    OPS,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER,
    USER
} from "../utils/Constants.sol";

contract FactoryTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Account private implementation;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory,,, implementation) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });
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

    function test_Constructor_CanUpgrade() public {
        assertEq(factory.canUpgrade(), true);
    }

    function test_Constructor_Implementation() public {
        assertEq(factory.implementation(), address(implementation));
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

    function test_UpdateAccountOwnership_AccountDoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.AccountDoesNotExist.selector)
        );
        vm.prank(address(0xCAFEBAE));
        factory.updateAccountOwnership(USER, address(this));
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

    function test_NewAccount_CannotBeInitialized() public {
        MockAccount1 mockAccount = new MockAccount1();
        factory.upgradeAccountImplementation({
            _implementation: address(mockAccount)
        });
        vm.expectRevert(
            abi.encodeWithSelector(IFactory.FailedToSetAcountOwner.selector, "")
        );
        factory.newAccount();
    }

    function test_NewAccount_CannotFetchVersion() public {
        MockAccount2 mockAccount = new MockAccount2();
        factory.upgradeAccountImplementation({
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
        vm.prank(address(0xBAE));
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
        vm.prank(address(0xA));
        factory.upgradeAccountImplementation({_implementation: address(0)});
    }

    function test_Upgrade_Implementation() public {
        // create account with old implementation
        address payable accountAddress = factory.newAccount();

        // transfer ownership to a specific address
        Account(accountAddress).transferOwnership(KWENTA_TREASURY);

        // deploy new implementation (that uses new Auth)
        UpgradedAccount newImplementation = new UpgradedAccount();

        // upgrade implementation via factory (beacon)
        factory.upgradeAccountImplementation({
            _implementation: address(newImplementation)
        });

        // check version changed
        bytes32 newVersion = "6.9.0";
        assertEq(Account(accountAddress).VERSION(), newVersion);

        // check owner did not change
        assertEq(Account(accountAddress).owner(), KWENTA_TREASURY);

        // check new account uses new implementation
        vm.prank(address(0xA));
        address payable accountAddress2 = factory.newAccount();
        assertEq(Account(accountAddress2).VERSION(), newVersion);
        assertEq(Account(accountAddress2).owner(), address(0xA));
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
}
