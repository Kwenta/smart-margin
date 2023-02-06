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

contract FactoryBehaviorTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    Settings private settings;
    Factory private factory;
    Account private implementation;

    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    uint256 private constant TRADE_FEE = 5;
    uint256 private constant LIMIT_ORDER_FEE = 5;
    uint256 private constant STOP_LOSS_FEE = 10;

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
            _settings: address(settings),
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
            _factory: address(factory)
        });
    }
}
