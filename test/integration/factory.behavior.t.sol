// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Settings} from "../../src/Settings.sol";
import {Factory} from "../../src/Factory.sol";
import {Account} from "../../src/Account.sol";
import {Events} from "../../src/Events.sol";

contract FactoryBehaviorTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    Settings private settings;
    Events private events;
    Factory private factory;
    Account private implementation;

    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    uint256 private tradeFee = 1;
    uint256 private limitOrderFee = 2;
    uint256 private stopOrderFee = 3;

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopOrderFee
        });

        events = new Events();

        implementation = new Account();

        factory = new Factory({
            _owner: address(this),
            _settings: address(settings),
            _events: address(events),
            _implementation: address(implementation)
        });
    }

    /*//////////////////////////////////////////////////////////////
                             CREATE ACCOUNT
    //////////////////////////////////////////////////////////////*/

    function testAccountOwnerSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.owner(), address(this));
    }

    function testAccountSettingsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.settings()), address(settings));
    }

    function testAccountEventsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.events()), address(events));
    }

    function testAccountFactorySet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.factory()), address(factory));
    }

    function testAccountVersionSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.VERSION(), bytes32("2.0.0"));
    }

    /*//////////////////////////////////////////////////////////////
                       IMPLEMENTATION INTERACTION
    //////////////////////////////////////////////////////////////*/

    function testImplementationOwnerShouldBeZeroAddress() public {
        assertEq(implementation.owner(), address(0));
    }

    function testCannotCallInitializeOnImplementation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize({
            _owner: address(this),
            _settings: address(settings),
            _events: address(events),
            _factory: address(factory)
        });
    }
}
