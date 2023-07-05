// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Setup} from "script/Deploy.s.sol";

import {Account} from "src/Account.sol";
import {Factory} from "src/Factory.sol";

import {ADDRESS_RESOLVER, BLOCK_NUMBER} from "test/utils/Constants.sol";

contract FactoryBehaviorTest is Test {
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
            _gelato: address(0),
            _ops: address(0),
            _universalRouter: address(0),
            _permit2: address(0)
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

    function test_Implementation_Owner() public {
        assertEq(implementation.owner(), address(0));
    }
}
