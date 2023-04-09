// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account, Auth} from "../../src/Account.sol";
import {AccountExposed} from "../utils/AccountExposed.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {
    IAccount,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated
} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {ISynth} from "../utils/interfaces/ISynth.sol";
import {ISystemStatus} from "../utils/interfaces/ISystemStatus.sol";
import {OpsReady, IOps} from "../../src/utils/OpsReady.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract OrderBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Factory private factory;
    Events private events;
    Account private account;
    ERC20 private sUSD;
    AccountExposed private accountExposed;
    uint256 private currentEthPriceInUSD;
    ISystemStatus systemStatus;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        Setup setup = new Setup();
        (factory, events,) = setup.deploySystem({
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });

        sUSD =
            ERC20((IAddressResolver(ADDRESS_RESOLVER)).getAddress("ProxysUSD"));
        address futuresMarketManager = IAddressResolver(ADDRESS_RESOLVER)
            .getAddress({name: bytes32("FuturesMarketManager")});
        systemStatus = ISystemStatus(
            IAddressResolver(ADDRESS_RESOLVER).getAddress({
                name: bytes32("SystemStatus")
            })
        );

        accountExposed =
        new AccountExposed(address(events), address(sUSD), futuresMarketManager, address(systemStatus), GELATO, OPS);

        account = Account(payable(factory.newAccount()));
        fundAccount(AMOUNT);

        currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(
                accountExposed.expose_getPerpsV2Market(sETHPERP)
            )
        );
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
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            address(account),
            orderId,
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
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            address(account),
            conditionalOrderId,
            IAccount
                .ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        );
        cancelConditionalOrder(conditionalOrderId);
    }

    /*//////////////////////////////////////////////////////////////
                 EXECUTING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Invalid_NotOps() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OpsReady.OnlyOps.selector));
        account.executeConditionalOrder({_conditionalOrderId: 0});
    }

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

        // suspend sAUDPERP market
        systemStatus.suspendFuturesMarket({marketKey: sAUDPERP, reason: 69});
        vm.stopPrank();

        // assert conditional order cannot be executed due to paused market
        (bool canExecute,) = account.checker(conditionalOrderId);
        assert(!canExecute);
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

        (uint256 desiredFillPrice,) = IPerpsV2MarketConsolidated(
            getMarketAddressFromKey(sETHPERP)
        ).assetPrice();

        submitAtomicOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            desiredFillPrice: desiredFillPrice
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
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        if (fuzzedSizeDelta > 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                IAccount
                    .ConditionalOrderCancelledReason
                    .CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
            );
        } else if (fuzzedSizeDelta < 0) {
            if (fuzzedSizeDelta + position.size < 0) {
                // expect fuzzedSizeDelta to be bound by zero to prevent flipping (long to short or vice versa)
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE
                });
            } else if (fuzzedSizeDelta + position.size >= 0) {
                // expect conditional order to be filled with specified fuzzedSizeDelta
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE
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
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        if (fuzzedSizeDelta < 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                IAccount
                    .ConditionalOrderCancelledReason
                    .CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
            );
        } else if (fuzzedSizeDelta > 0) {
            if (fuzzedSizeDelta + position.size > 0) {
                // expect fuzzedSizeDelta to be bound by zero to prevent flipping (long to short or vice versa)
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE
                });
            } else if (fuzzedSizeDelta + position.size <= 0) {
                // expect conditional order to be filled with specified fuzzedSizeDelta
                vm.expectEmit(true, true, true, true);
                emit ConditionalOrderFilled({
                    account: address(account),
                    conditionalOrderId: conditionalOrderId,
                    fillPrice: currentEthPriceInUSD,
                    keeperFee: GELATO_FEE
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
        sUSD.approve(address(account), amount);
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
