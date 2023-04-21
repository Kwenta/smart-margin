// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../utils/Constants.sol";
import {Account} from "../../src/Account.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {ISynth} from "../utils/interfaces/ISynth.sol";
import {Settings} from "../../src/Settings.sol";

contract UpgradeBehaviorTest is Test {
    /*//////////////////////////////////////////////////////////////
                       DEPLOYED CONTRACTS V2.0.0
    //////////////////////////////////////////////////////////////*/

    Factory private constant DEPLOYED_FACTORY =
        Factory(0x30582eeE34719fe22b1B6c3b607636A3ab94522E);
    Events private constant DEPLOYED_EVENTS =
        Events(0x8c3E12418d9327FAb68D6873FF274f181Cba99da);
    Account private constant DEPLOYED_ACCOUNT =
        Account(payable(0x3D0157ed46F43909425777084DB1e3CEeC55E781));

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Account private implementation;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // deploy the settings contract
        settings = new Settings({
            _owner: KWENTA_TREASURY
        });

        // resolve necessary addresses via the Synthetix Address Resolver
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        address futuresMarketManager =
            addressResolver.getAddress({name: bytes32("FuturesMarketManager")});
        address systemStatus =
            addressResolver.getAddress({name: bytes32("SystemStatus")});

        // deploy new account
        implementation = new Account({
            _factory: address(DEPLOYED_FACTORY),
            _events: address(DEPLOYED_EVENTS),
            _marginAsset: MARGIN_ASSET,
            _futuresMarketManager: futuresMarketManager,
            _systemStatus: systemStatus,
            _gelato: GELATO,
            _ops: OPS,
            _settings: address(settings)
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployed_Account_Version() public view {
        assert(DEPLOYED_ACCOUNT.VERSION() == "2.0.0");
    }

    function test_Upgrade_Implementation() public {
        // create smart margin account (v2.0.0)
        /// @dev DEPLOYED_FACTORY.newAccount() creates a v2.0.0 account
        /// but we use the new implementation Account type (i.e. v2.0.1).
        /// This is fine because the Account type is just a "wrapper" in this
        /// case and if a function is called which does not exist
        /// in the v2.0.0 account the call will revert.
        Account account = Account(DEPLOYED_FACTORY.newAccount());

        // mint sUSD to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend sUSD
        ERC20(MARGIN_ASSET).approve(address(account), AMOUNT);

        // deposit sUSD into account
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(AMOUNT);
        account.execute(commands, inputs);

        // submit condition order
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        inputs[0] = abi.encode(
            sETHPERP,
            int256(AMOUNT),
            int256(AMOUNT),
            1000 ether,
            IAccount.ConditionalOrderTypes.STOP,
            1000 ether,
            true
        );
        account.execute(commands, inputs);

        // add a delegate account just because..
        account.addDelegate(KWENTA_TREASURY);

        // check account is NOT 2.0.1
        assert(account.VERSION() != "2.0.1");

        // upgrade account implementation
        vm.prank(KWENTA_TREASURY);
        DEPLOYED_FACTORY.upgradeAccountImplementation(address(implementation));

        // check account was updated to 2.0.1
        assert(account.VERSION() == "2.0.1");

        // check state of account after upgrade did not change
        assert(account.owner() == address(this));
        assert(account.committedMargin() == AMOUNT);
        assert(account.conditionalOrderId() == 1);
        assert(account.getConditionalOrder(0).marketKey == sETHPERP);
        assert(account.getConditionalOrder(0).targetPrice == 1000 ether);
        assert(account.freeMargin() == 0);
        assert(account.delegates(KWENTA_TREASURY));

        // check execute() can be locked
        vm.prank(KWENTA_TREASURY);
        settings.setAccountExecutionEnabled(false);

        // try to execute a command
        vm.expectRevert(
            abi.encodeWithSelector(IAccount.AccountExecutionDisabled.selector)
        );
        account.execute(new IAccount.Command[](0), new bytes[](0));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function mintSUSD(address to, uint256 amount) private {
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD =
            ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }
}