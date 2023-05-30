// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/**
 * FOR REFERENCE ONLY
 *
 * import "forge-std/Test.sol";
 * import "../../utils/Constants.sol";
 * import "../../../script/utils/parameters/OptimismGoerliParameters.sol";
 * import {UpgradeAccountOptimismGoerli} from
 *     "../../../script/upgrades/v2.0.1/Upgrade.s.sol";
 * import {Account} from "../../../src/Account.sol";
 * import {ERC20} from "@solmate/tokens/ERC20.sol";
 * import {Events} from "../../../src/Events.sol";
 * import {Factory} from "../../../src/Factory.sol";
 * import {IAccount} from "../../../src/interfaces/IAccount.sol";
 * import {IAddressResolver} from "../../utils/interfaces/IAddressResolver.sol";
 * import {ISynth} from "../../utils/interfaces/ISynth.sol";
 * import {Settings} from "../../../src/Settings.sol";
 *
 * contract UpgradeTest is Test {
 *     Account private constant DEPLOYED_ACCOUNT =
 *         Account(payable(0x3D0157ed46F43909425777084DB1e3CEeC55E781));
 *
 *     Settings private settings;
 *     Events private events;
 *     Account private implementation;
 *
 *     function setUp() public {
 *         vm.rollFork(BLOCK_NUMBER);
 *
 *         // define Setup contract used for upgrades
 *         UpgradeAccountOptimismGoerli upgradeAccountOptimismGoerli =
 *             new UpgradeAccountOptimismGoerli();
 *
 *         // upgrade implementation and deploy the new settings contract
 *         (address implementationAddr, address settingsAddr, address eventsAddr) =
 *             upgradeAccountOptimismGoerli.upgrade();
 *         implementation = Account(payable(implementationAddr));
 *         settings = Settings(settingsAddr);
 *         events = Events(eventsAddr);
 *     }
 *
 *     function test_Deployed_Account_Version() public view {
 *         assert(DEPLOYED_ACCOUNT.VERSION() == "2.0.0");
 *     }
 *
 *     function test_Upgrade_Implementation_AccountExecutionEnabled() public {
 *         // create smart margin account (v2.0.0)
 *         /// @dev DEPLOYED_FACTORY.newAccount() creates a v2.0.0 account
 *         /// but we use the new implementation Account type (i.e. v2.0.1).
 *         /// This is fine because the Account type is just a "wrapper" in this
 *         /// case and if a function is called which does not exist
 *         /// in the v2.0.0 account the call will revert.
 *         Account account = Account(Factory(OPTIMISM_GOERLI_FACTORY).newAccount());
 *
 *         // mint sUSD to this address
 *         mintSUSD(address(this), AMOUNT);
 *
 *         // approve account to spend sUSD
 *         ERC20(MARGIN_ASSET).approve(address(account), AMOUNT);
 *
 *         // deposit sUSD into account
 *         IAccount.Command[] memory commands = new IAccount.Command[](1);
 *         commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
 *         bytes[] memory inputs = new bytes[](1);
 *         inputs[0] = abi.encode(AMOUNT);
 *         account.execute(commands, inputs);
 *
 *         // submit conditional order
 *         commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
 *         inputs[0] = abi.encode(
 *             sETHPERP,
 *             int256(AMOUNT),
 *             int256(AMOUNT),
 *             1000 ether,
 *             IAccount.ConditionalOrderTypes.STOP,
 *             1000 ether,
 *             true
 *         );
 *         account.execute(commands, inputs);
 *
 *         // add a delegate account just because..
 *         account.addDelegate(DELEGATE);
 *
 *         // check account is NOT 2.0.1
 *         assert(account.VERSION() != "2.0.1");
 *
 *         // upgrade account implementation
 *         vm.prank(OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG);
 *         Factory(OPTIMISM_GOERLI_FACTORY).upgradeAccountImplementation(
 *             address(implementation)
 *         );
 *
 *         // check account was updated to 2.0.1
 *         assert(account.VERSION() == "2.0.1");
 *
 *         // check state of account after upgrade did not change
 *         assert(account.owner() == address(this));
 *         assert(account.committedMargin() == AMOUNT);
 *         assert(account.conditionalOrderId() == 1);
 *         assert(account.getConditionalOrder(0).marketKey == sETHPERP);
 *         assert(account.getConditionalOrder(0).targetPrice == 1000 ether);
 *         assert(account.freeMargin() == 0);
 *         assert(account.delegates(DELEGATE));
 *
 *         // check execute() can be locked
 *         vm.prank(OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG);
 *         settings.setAccountExecutionEnabled(false);
 *
 *         // try to execute a command
 *         vm.expectRevert(
 *             abi.encodeWithSelector(IAccount.AccountExecutionDisabled.selector)
 *         );
 *         account.execute(new IAccount.Command[](0), new bytes[](0));
 *     }
 *
 *     function test_Upgrade_Implementation_Execute() public {
 *         // create smart margin account (v2.0.0)
 *         /// @dev DEPLOYED_FACTORY.newAccount() creates a v2.0.0 account
 *         /// but we use the new implementation Account type (i.e. v2.0.1).
 *         /// This is fine because the Account type is just a "wrapper" in this
 *         /// case and if a function is called which does not exist
 *         /// in the v2.0.0 account the call will revert.
 *         Account account = Account(Factory(OPTIMISM_GOERLI_FACTORY).newAccount());
 *
 *         // mint sUSD to this address
 *         mintSUSD(address(this), AMOUNT);
 *
 *         // approve account to spend sUSD
 *         ERC20(MARGIN_ASSET).approve(address(account), AMOUNT);
 *
 *         // deposit *some* sUSD into account
 *         IAccount.Command[] memory commands = new IAccount.Command[](1);
 *         commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
 *         bytes[] memory inputs = new bytes[](1);
 *         inputs[0] = abi.encode(AMOUNT / 2);
 *         account.execute(commands, inputs);
 *
 *         // upgrade account implementation
 *         vm.prank(OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG);
 *         Factory(OPTIMISM_GOERLI_FACTORY).upgradeAccountImplementation(
 *             address(implementation)
 *         );
 *
 *         // check account was updated to 2.0.1
 *         assert(account.VERSION() == "2.0.1");
 *
 *         // check state of account after upgrade did not change
 *         assert(account.freeMargin() == AMOUNT / 2);
 *
 *         // deposit sUSD into account
 *         commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
 *         inputs[0] = abi.encode(AMOUNT / 2);
 *         account.execute(commands, inputs);
 *
 *         // check state change
 *         assert(account.freeMargin() == AMOUNT);
 *     }
 *
 *     function test_Upgrade_Implementation_Execute_2() public {
 *         // create smart margin account (v2.0.0)
 *         /// @dev DEPLOYED_FACTORY.newAccount() creates a v2.0.0 account
 *         /// but we use the new implementation Account type (i.e. v2.0.1).
 *         /// This is fine because the Account type is just a "wrapper" in this
 *         /// case and if a function is called which does not exist
 *         /// in the v2.0.0 account the call will revert.
 *         Account account = Account(Factory(OPTIMISM_GOERLI_FACTORY).newAccount());
 *
 *         // mint sUSD to this address
 *         mintSUSD(address(this), AMOUNT);
 *
 *         // approve account to spend sUSD
 *         ERC20(MARGIN_ASSET).approve(address(account), AMOUNT);
 *
 *         // deposit sUSD into account
 *         IAccount.Command[] memory commands = new IAccount.Command[](1);
 *         commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
 *         bytes[] memory inputs = new bytes[](1);
 *         inputs[0] = abi.encode(AMOUNT);
 *         account.execute(commands, inputs);
 *
 *         // upgrade account implementation
 *         vm.prank(OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG);
 *         Factory(OPTIMISM_GOERLI_FACTORY).upgradeAccountImplementation(
 *             address(implementation)
 *         );
 *
 *         // check account was updated to 2.0.1
 *         assert(account.VERSION() == "2.0.1");
 *
 *         // submit conditional order
 *         commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
 *         inputs[0] = abi.encode(
 *             sETHPERP,
 *             int256(AMOUNT),
 *             int256(AMOUNT),
 *             1000 ether,
 *             IAccount.ConditionalOrderTypes.STOP,
 *             1000 ether,
 *             true
 *         );
 *         account.execute(commands, inputs);
 *     }
 *
 *     function mintSUSD(address to, uint256 amount) private {
 *         address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
 *         ISynth synthsUSD =
 *             ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
 *         vm.prank(issuer);
 *         synthsUSD.issue(to, amount);
 *     }
 * }
 */
