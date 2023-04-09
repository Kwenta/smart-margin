// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract FactoryBehaviorTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Factory private factory;
    Events private events;
    Account private implementation;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        Setup setup = new Setup();
        (factory, events, implementation) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             CREATE ACCOUNT
    //////////////////////////////////////////////////////////////*/

    function test_Account_OwnerSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.owner(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                       IMPLEMENTATION INTERACTION
    //////////////////////////////////////////////////////////////*/

    function test_Implementation_Owner_ZeroAddress() public {
        assertEq(implementation.owner(), address(0));
    }

    function test_CallInitialize_Implementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize({_owner: address(0), _factory: address(0)});
    }
}
