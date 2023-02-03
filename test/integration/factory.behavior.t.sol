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

    address private constant ADDRESS_RESOLVER =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address private SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address private constant GELATO_OPS =
        0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;
    address private constant FUTURES_MANAGER =
        0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B;

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
            _marginAsset: SUSD,
            _addressResolver: ADDRESS_RESOLVER,
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
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

    function testAccountMarginAssetSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.marginAsset()), SUSD);
    }

    function testAccountAddressResolverSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.addressResolver()), ADDRESS_RESOLVER);
    }

    function testAccountSettingsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(address(account.settings()), address(settings));
    }

    function testAccountGelatoOpsSet() public {
        address payable accountAddress = factory.newAccount();
        Account account = Account(accountAddress);
        assertEq(account.ops(), GELATO_OPS);
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
            _marginAsset: SUSD,
            _addressResolver: ADDRESS_RESOLVER,
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
            _factory: address(factory)
        });
    }
}
