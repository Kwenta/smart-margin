// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../utils/Constants.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "../utils/AccountExposed.sol";
import {Auth} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {IFuturesMarketManager} from "../../src/interfaces/IAccount.sol";
import {IPerpsV2MarketConsolidated} from "../../src/interfaces/IAccount.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";

contract AccountTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Settings private settings;
    Account private account;

    // helper contracts for testing
    AccountExposed private accountExposed;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory, events, settings,) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });

        // deploy an Account contract
        account = Account(payable(factory.newAccount()));

        // define helper contracts
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        address sUSD = addressResolver.getAddress(PROXY_SUSD);
        address futuresMarketManager =
            addressResolver.getAddress(FUTURES_MARKET_MANAGER);
        address systemStatus = addressResolver.getAddress(SYSTEM_STATUS);
        address perpsV2ExchangeRate =
            addressResolver.getAddress(PERPS_V2_EXCHANGE_RATE);

        // deploy AccountExposed contract for exposing internal account functions
        accountExposed = new AccountExposed(
            address(factory),
            address(events), 
            sUSD, 
            perpsV2ExchangeRate,
            futuresMarketManager, 
            systemStatus, 
            GELATO, 
            OPS,
            address(settings)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_GetVerison() public view {
        assert(account.VERSION() == "2.0.1");
    }

    function test_GetTrackingCode() public view {
        assert(accountExposed.expose_TRACKING_CODE() == "KWENTA");
    }

    function test_GetFactory() public view {
        assert(accountExposed.expose_FACTORY() == address(factory));
    }

    function test_GetEvents() public view {
        assert(accountExposed.expose_EVENTS() == address(events));
    }

    function test_GetMarginAsset() public view {
        assert(accountExposed.expose_MARGIN_ASSET() != address(0));
    }

    function test_GetFuturesMarketManager() public view {
        assert(accountExposed.expose_FUTURES_MARKET_MANAGER() != address(0));
    }

    function test_GetSystemStatus() public view {
        assert(accountExposed.expose_SYSTEM_STATUS() != address(0));
    }

    function test_GetGelato() public view {
        assert(accountExposed.expose_GELATO() == GELATO);
    }

    function test_GetOps() public view {
        assert(accountExposed.expose_OPS() == OPS);
    }

    function test_GetCommittedMargin() public view {
        assert(account.committedMargin() == 0);
    }

    function test_GetConditionalOrderId() public view {
        assert(account.conditionalOrderId() == 0);
    }

    function test_GetDelayedOrder_EthMarket() public {
        IPerpsV2MarketConsolidated.DelayedOrder memory delayedOrder =
            account.getDelayedOrder({_marketKey: sETHPERP});
        assertEq(delayedOrder.isOffchain, false);
        assertEq(delayedOrder.sizeDelta, 0);
        assertEq(delayedOrder.desiredFillPrice, 0);
        assertEq(delayedOrder.targetRoundId, 0);
        assertEq(delayedOrder.commitDeposit, 0);
        assertEq(delayedOrder.keeperDeposit, 0);
        assertEq(delayedOrder.executableAtTime, 0);
        assertEq(delayedOrder.intentionTime, 0);
        assertEq(delayedOrder.trackingCode, "");
    }

    function test_GetDelayedOrder_InvalidMarket() public {
        vm.expectRevert();
        account.getDelayedOrder({_marketKey: "unknown"});
    }

    function test_Checker() public {
        vm.expectRevert();
        account.checker({_conditionalOrderId: 0});
    }

    function test_GetFreeMargin() public {
        assertEq(account.freeMargin(), 0);
    }

    function test_GetPosition_EthMarket() public {
        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition({_marketKey: sETHPERP});
        assertEq(position.id, 0);
        assertEq(position.lastFundingIndex, 0);
        assertEq(position.margin, 0);
        assertEq(position.lastPrice, 0);
        assertEq(position.size, 0);
    }

    function test_GetPosition_InvalidMarket() public {
        vm.expectRevert();
        account.getPosition({_marketKey: "unknown"});
    }

    function test_GetConditionalOrder() public {
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder({_conditionalOrderId: 0});
        assertEq(conditionalOrder.marketKey, "");
        assertEq(conditionalOrder.marginDelta, 0);
        assertEq(conditionalOrder.sizeDelta, 0);
        assertEq(conditionalOrder.targetPrice, 0);
        assertEq(conditionalOrder.gelatoTaskId, "");
        assertEq(
            uint256(conditionalOrder.conditionalOrderType),
            uint256(IAccount.ConditionalOrderTypes.LIMIT)
        );
        assertEq(conditionalOrder.desiredFillPrice, 0);
        assertEq(conditionalOrder.reduceOnly, false);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @dev this is an indirect test that the factory address is set correctly
    function test_Ownership_Transfer() public {
        // ensure factory and account state align
        address originalOwner = factory.getAccountOwner(address(account));
        assert(
            originalOwner == address(this) && originalOwner == account.owner()
                && originalOwner != KWENTA_TREASURY
        );
        assert(factory.getAccountsOwnedBy(originalOwner)[0] == address(account));

        // transfer ownership
        account.transferOwnership(KWENTA_TREASURY);
        assert(account.owner() == KWENTA_TREASURY);

        // ensure factory and account state align
        address newOwner = factory.getAccountOwner(address(account));
        assert(newOwner == KWENTA_TREASURY && newOwner == account.owner());
        assert(
            factory.getAccountsOwnedBy(KWENTA_TREASURY)[0] == address(account)
        );
        assert(factory.getAccountsOwnedBy(originalOwner).length == 0);
    }

    function test_Ownership_Transfer_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), KWENTA_TREASURY);
        account.transferOwnership(KWENTA_TREASURY);
    }

    function test_Ownership_setInitialOwnership_OnlyFactory() public {
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.setInitialOwnership(KWENTA_TREASURY);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Margin_OnlyOwner() public {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(int256(AMOUNT));
    }

    function test_Withdraw_Margin_OnlyOwner() public {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(-int256(AMOUNT));
    }

    function test_Deposit_ETH_AnyCaller() public {
        account.transferOwnership(KWENTA_TREASURY);
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
    }

    function test_Withdraw_ETH_OnlyOwner() public {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        withdrawEth(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                               DELEGATION
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      ADD/REMOVE DELEGATED TRADERS
    //////////////////////////////////////////////////////////////*/

    function test_AddDelegatedTrader() public {
        account.addDelegate({_delegate: DELEGATE});
        assert(account.delegates(DELEGATE));
    }

    function test_AddDelegatedTrader_Event() public {
        vm.expectEmit(true, true, true, true);
        emit DelegatedAccountAdded(address(this), DELEGATE);
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_AddDelegatedTrader_OnlyOwner() public {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_AddDelegatedTrader_ZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, address(0)
            )
        );
        account.addDelegate({_delegate: address(0)});
    }

    function test_AddDelegatedTrader_AlreadyDelegated() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, DELEGATE
            )
        );
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader() public {
        account.addDelegate({_delegate: DELEGATE});
        account.removeDelegate({_delegate: DELEGATE});
        assert(!account.delegates(DELEGATE));
    }

    function test_RemoveDelegatedTrader_Event() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectEmit(true, true, true, true);
        emit DelegatedAccountRemoved(address(this), DELEGATE);
        account.removeDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader_OnlyOwner() public {
        account.addDelegate({_delegate: DELEGATE});
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.removeDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader_ZeroAddress() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, address(0)
            )
        );
        account.removeDelegate({_delegate: address(0)});
    }

    function test_RemoveDelegatedTrader_NotDelegated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, DELEGATE
            )
        );
        account.removeDelegate({_delegate: DELEGATE});
    }

    /*//////////////////////////////////////////////////////////////
                      DELEGATED TRADER PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function test_DelegatedTrader_TransferAccountOwnership() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.transferOwnership(DELEGATE);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    function test_Dispatch_InvalidCommand() public {
        bytes memory dataWithInvalidCommand = abi.encodeWithSignature(
            "execute(uint256,bytes)",
            69, // enums are rep as uint256 and there are not enough commands to reach 69
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IAccount.InvalidCommandType.selector, 69)
        );
        (bool s,) = address(account).call(dataWithInvalidCommand);
        assert(!s);
    }

    function test_Dispatch_ValidCommand_InvalidInput() public {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(69);
        vm.expectRevert();
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                           COMMAND EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The following commands *ARE NOT* allowed to be executed by a Delegate
     * @dev All commands can be executed by the owner and this behavior is tested in
     * test/integration/margin.behavior.t.sol and test/integration/order.behavior.t.sol
     */

    function test_DelegatedTrader_Execute_ACCOUNT_MODIFY_MARGIN() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);

        /// @notice delegate CANNOT execute the following COMMAND
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(int256(AMOUNT));
    }

    function test_DelegatedTrader_Execute_ACCOUNT_WITHDRAW_ETH() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);

        /// @notice delegate CANNOT execute the following COMMAND
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        withdrawEth(AMOUNT);
    }

    /**
     * @notice The following commands *ARE* allowed to be executed by a Delegate
     * @dev All commands can be executed by the owner and this behavior is tested in
     * test/integration/margin.behavior.t.sol and test/integration/order.behavior.t.sol
     */

    function test_DelegatedTrader_Execute_PERPS_V2_MODIFY_MARGIN() public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        inputs[0] =
            abi.encode(getMarketAddressFromKey(sETHPERP), int256(AMOUNT));

        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientFreeMargin.selector, 0, AMOUNT
            )
        );

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. insufficient free margin)
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_WITHDRAW_ALL_MARGIN()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);
        vm.expectCall(
            getMarketAddressFromKey(sETHPERP),
            abi.encodeWithSelector(
                IPerpsV2MarketConsolidated.withdrawAllMargin.selector
            )
        );

        /// @notice delegate CAN execute the following COMMAND
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_ATOMIC_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CLOSE_POSITION() public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] =
            IAccount.Command.PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no previous order in Synthetix market)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no previous order in Synthetix market)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_GELATO_PLACE_CONDITIONAL_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        inputs[0] = abi.encode(
            sETHPERP, 0, 0, 0, IAccount.ConditionalOrderTypes.LIMIT, 0, false
        );

        vm.prank(DELEGATE);

        /// @notice delegate CANNOT execute the following COMMAND
        vm.expectRevert(abi.encodeWithSelector(IAccount.ZeroSizeDelta.selector));
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_GELATO_CANCEL_CONDITIONAL_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.GELATO_CANCEL_CONDITIONAL_ORDER;
        inputs[0] = abi.encode(0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no task exists with id 0)
        vm.expectRevert("Automate.cancelTask: Task not found");
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                             EXECUTION LOCK
    //////////////////////////////////////////////////////////////*/

    function test_Execute_Locked() public {
        // lock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(false);

        // expect revert when calling execute
        vm.expectRevert(
            abi.encodeWithSelector(IAccount.AccountExecutionDisabled.selector)
        );
        account.execute(new IAccount.Command[](0), new bytes[](0));
    }

    function test_ExecuteConditionalOrder_Locked() public {
        // lock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(false);

        // expect revert when calling execute
        vm.expectRevert(
            abi.encodeWithSelector(IAccount.AccountExecutionDisabled.selector)
        );
        vm.prank(GELATO);
        account.executeConditionalOrder(1);
    }

    function test_Execute_CanUnlock() public {
        // lock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(false);

        // unlock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(true);

        // no-op that proves execute is not locked
        account.execute(new IAccount.Command[](0), new bytes[](0));
    }

    /*//////////////////////////////////////////////////////////////
                             MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    function test_Abs(int256 x) public view {
        if (x == 0) {
            assert(accountExposed.expose_abs(x) == 0);
        } else {
            assert(accountExposed.expose_abs(x) > 0);
        }
    }

    function test_IsSameSign(int256 x, int256 y) public {
        if (x == 0 || y == 0) {
            vm.expectRevert();
            accountExposed.expose_isSameSign(x, y);
        } else if (x > 0 && y > 0) {
            assert(accountExposed.expose_isSameSign(x, y));
        } else if (x < 0 && y < 0) {
            assert(accountExposed.expose_isSameSign(x, y));
        } else if (x > 0 && y < 0) {
            assert(!accountExposed.expose_isSameSign(x, y));
        } else if (x < 0 && y > 0) {
            assert(!accountExposed.expose_isSameSign(x, y));
        } else {
            assert(false);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
        // market and order related params
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress(
                        "FuturesMarketManager"
                    )
                ).marketForKey(key)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           COMMAND SHORTCUTS
    //////////////////////////////////////////////////////////////*/

    function modifyAccountMargin(int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function withdrawEth(uint256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }
}
