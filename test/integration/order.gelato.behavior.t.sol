// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Setup} from "script/Deploy.s.sol";

import {Account} from "src/Account.sol";
import {Auth} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IFuturesMarketManager} from
    "src/interfaces/synthetix/IFuturesMarketManager.sol";
import {IOps} from "src/interfaces/gelato/IOps.sol";
import {IPermit2} from "src/interfaces/uniswap/IPermit2.sol";
import {IPerpsV2MarketConsolidated} from
    "src/interfaces/synthetix/IPerpsV2MarketConsolidated.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {OpsReady} from "src/utils/gelato/OpsReady.sol";
import {Settings} from "src/Settings.sol";

import {AccountExposed} from "test/utils/AccountExposed.sol";
import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";
import {ISystemStatus} from "test/utils/interfaces/ISystemStatus.sol";

import {
    ADDRESS_RESOLVER,
    AMOUNT,
    BLOCK_NUMBER,
    DESIRED_FILL_PRICE,
    ETH,
    FUTURES_MARKET_MANAGER,
    GELATO,
    GELATO_FEE,
    OPS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    sAUDPERP,
    sETHPERP,
    SYSTEM_STATUS,
    TRACKING_CODE,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER,
    USER
} from "test/utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract OrderGelatoBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Settings private settings;
    Account private account;

    // helper contracts for testing
    IERC20 private sUSD;
    AccountExposed private accountExposed;
    ISystemStatus private systemStatus;

    // helper variables for testing
    uint256 private currentEthPriceInUSD;

    IPermit2 private PERMIT2;

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
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        // define helper contracts
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        sUSD = IERC20(addressResolver.getAddress(PROXY_SUSD));
        address futuresMarketManager =
            addressResolver.getAddress(FUTURES_MARKET_MANAGER);
        systemStatus = ISystemStatus(addressResolver.getAddress(SYSTEM_STATUS));
        address perpsV2ExchangeRate =
            addressResolver.getAddress(PERPS_V2_EXCHANGE_RATE);

        // deploy AccountExposed contract for exposing internal account functions
        IAccount.AccountConstructorParams memory params = IAccount
            .AccountConstructorParams(
            address(factory),
            address(events),
            address(sUSD),
            perpsV2ExchangeRate,
            futuresMarketManager,
            address(systemStatus),
            GELATO,
            OPS,
            address(settings),
            UNISWAP_UNIVERSAL_ROUTER,
            UNISWAP_PERMIT2
        );
        accountExposed = new AccountExposed(params);

        // deploy an Account contract and fund it
        account = Account(payable(factory.newAccount()));

        PERMIT2 = IPermit2(UNISWAP_PERMIT2);

        // get current ETH price in USD
        (currentEthPriceInUSD,) = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(
                accountExposed.expose_getPerpsV2Market(sETHPERP)
            )
        );

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        sUSD.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via PERMIT2_PERMIT in production
        PERMIT2.approve(
            address(sUSD), address(account), type(uint160).max, type(uint48).max
        );

        fundAccount(AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                  PLACING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Invalid_NotOwner() public {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            sETHPERP,
            0,
            int256(AMOUNT),
            0,
            IAccount.ConditionalOrderTypes.LIMIT,
            0,
            false
        );

        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        vm.prank(USER);
        account.execute(commands, inputs);
    }

    function test_PlaceConditionalOrder_Invalid_ZeroSizeDelta() public {
        vm.expectRevert(abi.encodeWithSelector(IAccount.ZeroSizeDelta.selector));
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            sETHPERP, 0, 0, 0, IAccount.ConditionalOrderTypes.LIMIT, 0, false
        );
        account.execute(commands, inputs);
    }

    function test_PlaceConditionalOrder_Invalid_InsufficientMargin() public {
        vm.prank(USER);
        account = Account(payable(factory.newAccount()));
        vm.deal(address(account), 1 ether);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            sETHPERP,
            int256(AMOUNT),
            int256(AMOUNT),
            0,
            IAccount.ConditionalOrderTypes.LIMIT,
            0,
            false
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientFreeMargin.selector, 0, int256(AMOUNT)
            )
        );
        vm.prank(USER);
        account.execute(commands, inputs);
    }

    function test_PlaceConditionalOrder_Valid_GelatoTaskId() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        (, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // get task id
        bytes32 taskId = IOps(OPS).getTaskId({
            taskCreator: address(account),
            execAddress: address(account),
            execSelector: account.executeConditionalOrder.selector,
            moduleData: moduleData,
            feeToken: ETH
        });

        // check account recorded task id matches gelato task id fetched
        assertEq(
            taskId, account.getConditionalOrder(conditionalOrderId).gelatoTaskId
        );
    }

    /*//////////////////////////////////////////////////////////////
                   PLACING CONDITIONAL ORDERS: LIMIT
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Limit_Valid_Long(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice >= currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Invalid_Long(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice < currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Valid_Short(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice <= currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: -int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Invalid_Short(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice > currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: -int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Valid_State(
        int256 fuzzedSizeDelta
    ) public {
        vm.assume(fuzzedSizeDelta != 0);
        uint256 orderId = account.conditionalOrderId();
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: fuzzedSizeDelta,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        // check conditionalOrderId incremented
        assertTrue(account.conditionalOrderId() == orderId + 1);
        assertTrue(conditionalOrderId == orderId);
        // check order was registered internally
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(orderId);
        assertTrue(conditionalOrder.marketKey == sETHPERP);
        assertTrue(conditionalOrder.marginDelta == int256(currentEthPriceInUSD));
        assertTrue(conditionalOrder.sizeDelta == fuzzedSizeDelta);
        assertTrue(conditionalOrder.targetPrice == currentEthPriceInUSD);
        assertTrue(
            uint256(conditionalOrder.conditionalOrderType)
                == uint256(IAccount.ConditionalOrderTypes.LIMIT)
        );
        assertTrue(conditionalOrder.gelatoTaskId != 0); // this is set by Gelato
        assertTrue(conditionalOrder.desiredFillPrice == DESIRED_FILL_PRICE);
        assertFalse(conditionalOrder.reduceOnly);
    }

    function test_PlaceConditionalOrder_Limit_Valid_Event(
        int256 fuzzedSizeDelta
    ) public {
        vm.assume(fuzzedSizeDelta != 0);
        uint256 orderId = account.conditionalOrderId();

        (, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(orderId);

        bytes32 taskId = IOps(OPS).getTaskId({
            taskCreator: address(account),
            execAddress: address(account),
            execSelector: account.executeConditionalOrder.selector,
            moduleData: moduleData,
            feeToken: ETH
        });

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            address(account),
            orderId,
            taskId,
            sETHPERP,
            int256(currentEthPriceInUSD),
            fuzzedSizeDelta,
            currentEthPriceInUSD,
            IAccount.ConditionalOrderTypes.LIMIT,
            DESIRED_FILL_PRICE,
            false
        );
        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: fuzzedSizeDelta,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                    PLACING CONDITIONAL ORDERS: STOP
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Stop_Valid_Long(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice <= currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Invalid_Long(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice > currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Valid_Short(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice >= currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: -int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Invalid_Short(
        uint256 fuzzedTargetPrice
    ) public {
        vm.assume(fuzzedTargetPrice < currentEthPriceInUSD);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: -int256(AMOUNT),
            targetPrice: fuzzedTargetPrice,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Invalid_OrderType() public {
        (bool success,) = address(accountExposed).call(
            abi.encodeWithSelector(
                AccountExposed.expose_placeConditionalOrder.selector,
                sETHPERP,
                int256(AMOUNT),
                int256(AMOUNT),
                currentEthPriceInUSD,
                69, // bad conditional order type
                DESIRED_FILL_PRICE,
                false
            )
        );
        assertFalse(success);
    }

    /*//////////////////////////////////////////////////////////////
                   PLACING CONDITIONAL ORDERS: MARGIN
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_CommittingMargin_Deposit() public {
        assertEq(account.committedMargin(), 0);
        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        assertEq(account.committedMargin(), AMOUNT);
    }

    function test_PlaceConditionalOrder_CommittingMargin_Withdraw(
        uint256 fuzzedCommitedMargin,
        int256 fuzzedAmountToWithdraw
    ) public {
        vm.assume(fuzzedCommitedMargin != 0);
        vm.assume(fuzzedCommitedMargin <= AMOUNT);
        vm.assume(fuzzedAmountToWithdraw < 0);

        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(fuzzedCommitedMargin),
            sizeDelta: int256(AMOUNT),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        uint256 freeMargin = AMOUNT - fuzzedCommitedMargin;

        if (freeMargin == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector,
                    0,
                    accountExposed.expose_abs(fuzzedAmountToWithdraw)
                )
            );
        } else if (
            accountExposed.expose_abs(fuzzedAmountToWithdraw) > freeMargin
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector,
                    freeMargin,
                    accountExposed.expose_abs(fuzzedAmountToWithdraw)
                )
            );
        }

        modifyAccountMargin(fuzzedAmountToWithdraw);
    }

    function test_PlaceConditionalOrder_Invalid_InsufficientFreeMargin()
        public
    {
        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientFreeMargin.selector, 0, AMOUNT
            )
        );
        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                 CANCELING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_CancelConditionalOrder_Invalid_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        cancelConditionalOrder({conditionalOrderId: 0});
    }

    function test_CancelConditionalOrder_Nonexistent(
        uint256 fuzzedConditionalOrderId
    ) public {
        vm.expectRevert("Automate.cancelTask: Task not found");
        cancelConditionalOrder(fuzzedConditionalOrderId);
    }

    function test_CancelConditionalOrder_State() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: int256(currentEthPriceInUSD),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        cancelConditionalOrder(conditionalOrderId);
        // check order was removed internally
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == "");
        assert(conditionalOrder.marginDelta == 0);
        assert(conditionalOrder.sizeDelta == 0);
        assert(conditionalOrder.targetPrice == 0);
        assert(uint256(conditionalOrder.conditionalOrderType) == 0);
        assert(conditionalOrder.gelatoTaskId == 0);
        assert(conditionalOrder.desiredFillPrice == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_CancelConditionalOrder_Margin() public {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: int256(currentEthPriceInUSD),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        uint256 postCommittedMargin = account.committedMargin();
        assertEq(preCommittedMargin, postCommittedMargin - currentEthPriceInUSD);
        cancelConditionalOrder(conditionalOrderId);
        assertEq(account.committedMargin(), preCommittedMargin);
    }

    function test_CancelConditionalOrder_Event() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: int256(currentEthPriceInUSD),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);

        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            address(account),
            conditionalOrderId,
            conditionalOrder.gelatoTaskId,
            IAccount
                .ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        );

        cancelConditionalOrder(conditionalOrderId);
    }

    /*//////////////////////////////////////////////////////////////
                 EXECUTING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_MarketIsPaused() public {
        // place conditional order for sAUDPERP market
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sAUDPERP,
            marginDelta: int256(AMOUNT),
            sizeDelta: int256(AMOUNT),
            targetPrice: 0,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: 0,
            reduceOnly: false
        });

        // pause sAUDPERP market
        suspendPerpsV2Market(sAUDPERP);

        // assert conditional order cannot be executed due to paused market
        (bool canExecute,) = account.checker(conditionalOrderId);
        assert(!canExecute);
    }

    function test_ExecuteConditionalOrder_AfterUnlock() public {
        // lock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(false);

        // unlock accounts as settings owner (which is this address)
        settings.setAccountExecutionEnabled(true);

        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    // assert successful execution frees committed margin
    function test_ExecuteConditionalOrder_Valid_GelatoFee() public {
        uint256 existingGelatoBalance = GELATO.balance;
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        assertEq(GELATO.balance, existingGelatoBalance + GELATO_FEE);
    }

    // assert fee transfer to gelato is called
    function test_ExecuteConditionalOrder_Valid_FeeTransfer() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        // expect a call w/ empty calldata to gelato (payment through callvalue)
        vm.expectCall(GELATO, "");
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    // assert fee transfer to gelato is called when for a reduce only order that
    // is not filled due to it being an invalid reduce only order
    function test_ExecuteConditionalOrder_Valid_InvalidReduceOnly_InactiveMarket_FeeTransfer(
    ) public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        // expect a call w/ empty calldata to gelato (payment through callvalue)
        vm.expectCall(GELATO, "");
        vm.prank(GELATO);

        // market does not have an active position and the conditional order is reduce only
        // but a fee should still be paid to gelato for execution
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    // assert fee transfer to gelato is called when for a reduce only order that
    // is not filled due to it being an invalid reduce only order
    function test_ExecuteConditionalOrder_Valid_InvalidReduceOnly_SameSign_FeeTransfer(
    ) public {
        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        // create and place a conditional order that is reduce only
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether, // this is the same sign as the pre-existing position
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // expect a call w/ empty calldata to gelato (payment through callvalue)
        vm.expectCall(GELATO, "");
        vm.prank(GELATO);

        // the incoming conditional order size delta is the same sign,
        // thus the conditional order is not reduce only;
        // a fee should still be paid to gelato for execution
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    function test_ExecuteConditionalOrder_Valid_InsufficientEth() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        withdrawEthFromAccount(1 ether);

        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        /// @dev gelato gets revert message defined in Kwenta's OpsReady contract
        /// and for whatever reason modifies it, thus the error message we expect
        /// is different from what is defined in our OpsReady contract
        ///
        /// kwenta's: "OpsReady: ETH transfer failed"
        /// gelato's: "Automate.exec: OpsReady: ETH transfer failed"
        vm.expectRevert("Automate.exec: OpsReady: ETH transfer failed");

        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    // assert fee transfer to gelato is called
    function test_ExecuteConditionalOrder_Valid_TaskRemovedFromGelato()
        public
    {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });

        // attempt to execute the same task again
        vm.expectRevert("Automate.exec: Task not found");
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    function test_ExecuteConditionalOrder_Valid_TaskCancelled() public {
        // place conditional order
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD * 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        // check task id registered in gelato
        bytes32 taskId =
            account.getConditionalOrder(conditionalOrderId).gelatoTaskId;
        bytes32[] memory outstandingTasks =
            IOps(OPS).getTaskIdsByUser(address(account));
        assertEq(outstandingTasks.length, 1);
        assertEq(taskId, outstandingTasks[0]);

        // define module data within test that matches the module data submitted to gelato
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // prank gelato and execute task
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });

        // ensure task is cancelled (i.e. gelato task is removed)
        outstandingTasks = IOps(OPS).getTaskIdsByUser(address(account));
        assertEq(outstandingTasks.length, 0);
    }

    function test_ExecuteConditionalOrder_InvalidAtExecutionTime() public {
        // place conditional order
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD * 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        // define task id
        bytes32 taskId =
            account.getConditionalOrder(conditionalOrderId).gelatoTaskId;

        // define module data within test that matches the module data submitted to gelato
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // suspend market so execution will fail (not this will never happen due to the checker
        // catching this before gelato executes the task). This is done
        // here just to replicate the execution failing, regardless of the reason
        suspendPerpsV2Market(sETHPERP);

        // prank gelato and execute task (note this will fail)
        vm.prank(GELATO);
        try IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        }) {} catch {
            // ensure task still exists
            // ensure task is cancelled (i.e. gelato task is removed)
            bytes32[] memory outstandingTasks =
                IOps(OPS).getTaskIdsByUser(address(account));
            assertEq(outstandingTasks.length, 1);
            assertEq(taskId, outstandingTasks[0]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                  EXECUTING CONDITIONAL ORDERS: LIMIT
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Limit_Valid_Margin() public {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD * 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        uint256 postCommittedMargin = account.committedMargin();
        assertEq(preCommittedMargin, postCommittedMargin - currentEthPriceInUSD);
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // expect committed margin to decrease by currentEthPriceInUSD
        assertEq(account.committedMargin(), preCommittedMargin);
    }

    function test_ExecuteConditionalOrder_Limit_Valid_State() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD * 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // check internal state was updated
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == "");
        assert(conditionalOrder.marginDelta == 0);
        assert(conditionalOrder.sizeDelta == 0);
        assert(conditionalOrder.targetPrice == 0);
        assert(uint256(conditionalOrder.conditionalOrderType) == 0);
        assert(conditionalOrder.gelatoTaskId == 0);
        assert(conditionalOrder.desiredFillPrice == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ExecuteConditionalOrder_Limit_Valid_Synthetix() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD * 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        // confirm delayed order details are non-zero
        assert(order.isOffchain == true);
        assert(order.sizeDelta == 1 ether);
        assert(order.desiredFillPrice == DESIRED_FILL_PRICE);
        assert(order.targetRoundId == 0); // off chain doesn’t use internal oracle so it’ll always be zero
        assert(order.commitDeposit == 0); // no commit deposit post Almach release
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime == 0); // only used for delayed (on-chain)
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                   EXECUTING CONDITIONAL ORDERS: STOP
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Stop_Valid_Margin() public {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD / 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        uint256 postCommittedMargin = account.committedMargin();
        assertEq(preCommittedMargin, postCommittedMargin - currentEthPriceInUSD);
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // expect committed margin to decrease by currentEthPriceInUSD
        assertEq(account.committedMargin(), preCommittedMargin);
    }

    function test_ExecuteConditionalOrder_Stop_Valid_State() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD / 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // check internal state was updated
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == "");
        assert(conditionalOrder.marginDelta == 0);
        assert(conditionalOrder.sizeDelta == 0);
        assert(conditionalOrder.targetPrice == 0);
        assert(uint256(conditionalOrder.conditionalOrderType) == 0);
        assert(conditionalOrder.gelatoTaskId == 0);
        assert(conditionalOrder.desiredFillPrice == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ExecuteConditionalOrder_Stop_Valid_Synthetix() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD / 2,
            conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        // confirm delayed order details are non-zero
        assert(order.isOffchain == true);
        assert(order.sizeDelta == 1 ether);
        assert(order.desiredFillPrice == DESIRED_FILL_PRICE);
        assert(order.targetRoundId == 0); // off chain doesn’t use internal oracle so it’ll always be zero
        assert(order.commitDeposit == 0); // no commit deposit post Almach release
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime == 0); // only used for delayed (on-chain)
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                              REDUCE ONLY
    //////////////////////////////////////////////////////////////*/

    function test_ReduceOnlyOrder_Valid_State() public {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(currentEthPriceInUSD);
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: 0,
            sizeDelta: -(1 ether / 2),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // expect conditional order to be cancelled post-execution
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == "");
        assert(conditionalOrder.marginDelta == 0);
        assert(conditionalOrder.sizeDelta == 0);
        assert(conditionalOrder.targetPrice == 0);
        assert(uint256(conditionalOrder.conditionalOrderType) == 0);
        assert(conditionalOrder.gelatoTaskId == 0);
        assert(conditionalOrder.desiredFillPrice == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ReduceOnlyOrder_Valid_Synthetix() public {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(currentEthPriceInUSD);
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: 0,
            sizeDelta: -(1 ether / 2),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: desiredFillPrice,
            reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        // expect all details to be unset
        assert(order.isOffchain == true);
        assert(order.sizeDelta != 0);
        assert(order.desiredFillPrice != 0);
        assert(order.targetRoundId == 0); // off chain doesn’t use internal oracle so it’ll always be zero
        assert(order.commitDeposit == 0); // no commit deposit post Almach release
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime == 0); // only used for delayed (on-chain)
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    function test_ReduceOnlyOrder_Valid_Long(int256 fuzzedSizeDelta) public {
        vm.assume(fuzzedSizeDelta != 0);

        submitAtomicOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            desiredFillPrice: currentEthPriceInUSD
        });

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        assert(position.size == 1 ether); // sanity check :D

        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: 0,
            sizeDelta: fuzzedSizeDelta,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: currentEthPriceInUSD,
            reduceOnly: true
        });

        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);

        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        if (fuzzedSizeDelta > 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                conditionalOrder.gelatoTaskId,
                IAccount
                    .ConditionalOrderCancelledReason
                    .CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
            );
        } else if (fuzzedSizeDelta < 0) {
            if (fuzzedSizeDelta + position.size < 0) {
                // expect fuzzedSizeDelta to be bound by zero to prevent
                // flipping (long to short or vice versa)
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    gelatoTaskId: conditionalOrder.gelatoTaskId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE,
                    priceOracle: IAccount.PriceOracleUsed.PYTH
                });
            } else if (fuzzedSizeDelta + position.size >= 0) {
                // expect conditional order to be filled with specified fuzzedSizeDelta
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    gelatoTaskId: conditionalOrder.gelatoTaskId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE,
                    priceOracle: IAccount.PriceOracleUsed.PYTH
                });
            } else {
                revert("Uncaught case");
            }
        } else {
            revert("Uncaught case");
        }

        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    function test_ReduceOnlyOrder_Valid_Short(int256 fuzzedSizeDelta) public {
        vm.assume(fuzzedSizeDelta != 0);
        submitAtomicOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: -1 ether,
            desiredFillPrice: 1 ether / 2
        });

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        assert(position.size == -1 ether); // sanity check :D

        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: 0,
            sizeDelta: fuzzedSizeDelta,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });

        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);

        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        if (fuzzedSizeDelta < 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                conditionalOrder.gelatoTaskId,
                IAccount
                    .ConditionalOrderCancelledReason
                    .CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
            );
        } else if (fuzzedSizeDelta > 0) {
            if (fuzzedSizeDelta + position.size > 0) {
                // expect fuzzedSizeDelta to be bound by zero to prevent
                // flipping (long to short or vice versa)
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    gelatoTaskId: conditionalOrder.gelatoTaskId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE,
                    priceOracle: IAccount.PriceOracleUsed.PYTH
                });
            } else if (fuzzedSizeDelta + position.size <= 0) {
                // expect conditional order to be filled with specified fuzzedSizeDelta
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    gelatoTaskId: conditionalOrder.gelatoTaskId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE,
                    priceOracle: IAccount.PriceOracleUsed.PYTH
                });
            } else {
                revert("Uncaught case");
            }
        } else {
            revert("Uncaught case");
        }

        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-STEP INTERACTIONS
    //////////////////////////////////////////////////////////////*/

    /// 1. Place conditional order (limit)
    /// 2. Execute conditional order (as Gelato)
    /// 3. Cancel pending Synthetix delayed order
    function test_ConditionalOrder_Limit_Valid_Execute_Cancel() public {
        uint256 conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        vm.prank(GELATO);
        IOps(OPS).exec({
            taskCreator: address(account),
            execAddress: address(account),
            execData: executionData,
            moduleData: moduleData,
            txFee: GELATO_FEE,
            feeToken: ETH,
            useTaskTreasuryFunds: false,
            revertOnFailure: true
        });
        // fast forward time
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 600 seconds);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.desiredFillPrice == 0);
        assert(order.targetRoundId == 0);
        assert(order.commitDeposit == 0);
        assert(order.keeperDeposit == 0);
        assert(order.executableAtTime == 0);
        assert(order.intentionTime == 0);
        assert(order.trackingCode == "");
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

    function fundAccount(uint256 amount) private {
        vm.deal(address(account), 1 ether);
        mintSUSD(address(this), amount);
        modifyAccountMargin({amount: int256(amount)});
    }

    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
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

    function generateGelatoModuleData(uint256 conditionalOrderId)
        internal
        view
        returns (bytes memory executionData, IOps.ModuleData memory moduleData)
    {
        executionData =
            abi.encodeCall(account.executeConditionalOrder, conditionalOrderId);

        moduleData = IOps.ModuleData({
            modules: new IOps.Module[](1),
            args: new bytes[](1)
        });

        moduleData.modules[0] = IOps.Module.RESOLVER;

        moduleData.args[0] = abi.encode(
            address(account),
            abi.encodeCall(account.checker, conditionalOrderId)
        );
    }

    function suspendPerpsV2Market(bytes32 market) internal {
        // fetch owner address of SystemStatus contract
        (bool success, bytes memory response) =
            address(systemStatus).call(abi.encodeWithSignature("owner()"));
        address systemStatusOwner =
            success ? abi.decode(response, (address)) : address(0);

        // add owner to access control list so they can suspend perpsv2 market
        vm.startPrank(systemStatusOwner);
        systemStatus.updateAccessControl({
            section: bytes32("Futures"),
            account: systemStatusOwner,
            canSuspend: true,
            canResume: true
        });

        // suspend market
        systemStatus.suspendFuturesMarket({marketKey: market, reason: 69});
        vm.stopPrank();
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

    function withdrawEthFromAccount(uint256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_WITHDRAW_ETH;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function submitAtomicOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) private {
        address market = getMarketAddressFromKey(marketKey);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);
    }

    function placeConditionalOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint256 desiredFillPrice,
        bool reduceOnly
    ) private returns (uint256 conditionalOrderId) {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            marketKey,
            marginDelta,
            sizeDelta,
            targetPrice,
            conditionalOrderType,
            desiredFillPrice,
            reduceOnly
        );
        account.execute(commands, inputs);
        conditionalOrderId = account.conditionalOrderId() - 1;
    }

    function cancelConditionalOrder(uint256 conditionalOrderId) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_CANCEL_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(conditionalOrderId);
        account.execute(commands, inputs);
    }
}
