// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

contract FactoryBehaviorTest is Test, ConsolidatedEvents {
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
                             CREATE ACCOUNT
    //////////////////////////////////////////////////////////////*/

    function test_Account_OwnerSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.owner(), address(this));
    }

    function test_Account_SettingsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.settings()), address(settings));
    }

    function test_Account_EventsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.events()), address(events));
    }

    function test_Account_FactorySet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.factory()), address(factory));
    }

    function test_Account_VersionSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.VERSION(), bytes32("2.0.0"));
    }

    /*//////////////////////////////////////////////////////////////
                       IMPLEMENTATION INTERACTION
    //////////////////////////////////////////////////////////////*/

    function test_Implementation_Owner_ZeroAddress() public {
        assertEq(implementation.owner(), address(0));
    }

    function test_CallInitialize_Implementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize({
            _owner: address(this),
            _settings: address(settings),
            _events: address(events),
            _factory: address(factory)
        });
    }
}
