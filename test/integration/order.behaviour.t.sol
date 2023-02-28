// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
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
import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {IPerpsV2MarketSettings} from "@synthetix/IPerpsV2MarketSettings.sol";
import {ISynth} from "@synthetix/ISynth.sol";
import {OpsReady, IOps} from "../../src/utils/OpsReady.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract OrderBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Events private events;
    Factory private factory;
    Account private account;
    ERC20 private sUSD;
    AccountExposed private accountExposed;
    uint256 private currentEthPriceInUSD;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // establish sUSD address
        sUSD = ERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress("ProxyERC20sUSD"));

        // uses deployment script for tests (2 birds 1 stone)
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: TRADE_FEE,
            limitOrderFee: LIMIT_ORDER_FEE,
            stopOrderFee: STOP_ORDER_FEE
        });

        settings = Settings(factory.settings());
        events = Events(factory.events());
        account = createAccountAndDepositSUSD(AMOUNT);

        // deploy contract that exposes Account's internal functions
        accountExposed = new AccountExposed();
        accountExposed.setSettings(settings);
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));

        // fetch ETH amount in sUSD
        currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                  PLACING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Invalid_NotOwner() external {
        vm.prank(USER);
        vm.expectRevert("UNAUTHORIZED");
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: int256(AMOUNT),
            _targetPrice: 0,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: 0,
            _reduceOnly: false
        });
    }

    function test_PlaceConditionalOrder_Invalid_ZeroSizeDelta() external {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, bytes32("_sizeDelta"))
        );
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: 0,
            _targetPrice: 0,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: 0,
            _reduceOnly: false
        });
    }

    function test_PlaceConditionalOrder_Invalid_InsufficientETH() external {
        vm.prank(USER);
        account = createAccount();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientEthBalance.selector, address(account).balance, MIN_ETH
            )
        );
        vm.prank(USER);
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: int256(AMOUNT),
            _targetPrice: 0,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: 0,
            _reduceOnly: false
        });
    }

    function test_PlaceConditionalOrder_Invalid_InsufficientMargin() external {
        vm.prank(USER);
        account = createAccount();
        vm.deal(address(account), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IAccount.InsufficientFreeMargin.selector, 0, int256(AMOUNT))
        );
        vm.prank(USER);
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: 0,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: 0,
            _reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                   PLACING CONDITIONAL ORDERS: LIMIT
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Limit_Valid_Long(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice >= currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Invalid_Long(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice < currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Valid_Short(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice <= currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: -int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Invalid_Short(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice > currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: -int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Limit_Valid_State(int256 fuzzedSizeDelta) external {
        vm.assume(fuzzedSizeDelta != 0);
        uint256 orderId = account.conditionalOrderId();
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: fuzzedSizeDelta,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        // check conditionalOrderId incremented
        assertTrue(account.conditionalOrderId() == orderId + 1);
        assertTrue(conditionalOrderId == orderId);
        // check order was registered internally
        IAccount.ConditionalOrder memory conditionalOrder = account.getConditionalOrder(orderId);
        assertTrue(conditionalOrder.marketKey == sETHPERP);
        assertTrue(conditionalOrder.marginDelta == int256(currentEthPriceInUSD));
        assertTrue(conditionalOrder.sizeDelta == fuzzedSizeDelta);
        assertTrue(conditionalOrder.targetPrice == currentEthPriceInUSD);
        assertTrue(
            uint256(conditionalOrder.conditionalOrderType)
                == uint256(IAccount.ConditionalOrderTypes.LIMIT)
        );
        assertTrue(conditionalOrder.gelatoTaskId != 0); // this is set by Gelato
        assertTrue(conditionalOrder.priceImpactDelta == PRICE_IMPACT_DELTA);
        assertFalse(conditionalOrder.reduceOnly);
    }

    function test_PlaceConditionalOrder_Limit_Valid_Event(int256 fuzzedSizeDelta) external {
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
            PRICE_IMPACT_DELTA,
            false
            );
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: fuzzedSizeDelta,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                    PLACING CONDITIONAL ORDERS: STOP
    //////////////////////////////////////////////////////////////*/

    function test_PlaceConditionalOrder_Stop_Valid_Long(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice <= currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Invalid_Long(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice > currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Valid_Short(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice >= currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: -int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertTrue(canExec);
    }

    function test_PlaceConditionalOrder_Stop_Invalid_Short(uint256 fuzzedTargetPrice) public {
        vm.assume(fuzzedTargetPrice < currentEthPriceInUSD);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: -int256(AMOUNT),
            _targetPrice: fuzzedTargetPrice,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        (bool canExec,) = account.checker(conditionalOrderId);
        assertFalse(canExec);
    }

    function test_PlaceConditionalOrder_Invalid_OrderType() public {
        (bool success,) = address(account).call(
            abi.encodeWithSelector(
                account.placeConditionalOrder.selector,
                sETHPERP,
                int256(AMOUNT),
                int256(AMOUNT),
                currentEthPriceInUSD,
                69, // bad conditional order type
                PRICE_IMPACT_DELTA,
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
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        assertEq(account.committedMargin(), AMOUNT);
    }

    function test_PlaceConditionalOrder_CommittingMargin_Withdraw(
        uint256 fuzzedCommitedMargin,
        uint256 fuzzedAmountToWithdraw
    ) public {
        vm.assume(fuzzedCommitedMargin > 0);
        vm.assume(fuzzedCommitedMargin <= AMOUNT);
        vm.assume(fuzzedAmountToWithdraw > 0);
        assertEq(account.committedMargin(), 0);
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(fuzzedCommitedMargin),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        uint256 freeMargin = AMOUNT - fuzzedCommitedMargin;
        if (freeMargin == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector, 0, fuzzedAmountToWithdraw
                )
            );
        } else if (fuzzedAmountToWithdraw > freeMargin) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector, freeMargin, fuzzedAmountToWithdraw
                )
            );
        }
        account.withdraw(fuzzedAmountToWithdraw);
    }

    function test_PlaceConditionalOrder_Invalid_InsufficientFreeMargin() public {
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        vm.expectRevert(abi.encodeWithSelector(IAccount.InsufficientFreeMargin.selector, 0, AMOUNT));
        account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(AMOUNT),
            _sizeDelta: int256(AMOUNT),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                 CANCELING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_CancelConditionalOrder_Invalid_NotOwner() external {
        vm.prank(USER);
        vm.expectRevert("UNAUTHORIZED");
        account.cancelConditionalOrder({_conditionalOrderId: 0});
    }

    function test_CancelConditionalOrder_Nonexistent(uint256 fuzzedConditionalOrderId) external {
        vm.expectRevert();
        account.cancelConditionalOrder(fuzzedConditionalOrderId);
    }

    function test_CancelConditionalOrder_State() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: int256(currentEthPriceInUSD),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        account.cancelConditionalOrder(conditionalOrderId);
        // check order was removed internally
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == "");
        assert(conditionalOrder.marginDelta == 0);
        assert(conditionalOrder.sizeDelta == 0);
        assert(conditionalOrder.targetPrice == 0);
        assert(uint256(conditionalOrder.conditionalOrderType) == 0);
        assert(conditionalOrder.gelatoTaskId == 0);
        assert(conditionalOrder.priceImpactDelta == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_CancelConditionalOrder_Margin() external {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: int256(currentEthPriceInUSD),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        uint256 postCommittedMargin = account.committedMargin();
        assertEq(preCommittedMargin, postCommittedMargin - currentEthPriceInUSD);
        account.cancelConditionalOrder(conditionalOrderId);
        assertEq(account.committedMargin(), preCommittedMargin);
    }

    function test_CancelConditionalOrder_Event() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: int256(currentEthPriceInUSD),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            address(account),
            conditionalOrderId,
            IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER
            );
        account.cancelConditionalOrder(conditionalOrderId);
    }

    /*//////////////////////////////////////////////////////////////
                 EXECUTING CONDITIONAL ORDERS: GENERAL
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Invalid_NotOps() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OpsReady.OnlyOps.selector));
        account.executeConditionalOrder({_conditionalOrderId: 0});
    }

    // assert successful execution frees committed margin
    function test_ExecuteConditionalOrder_Valid_GelatoFee() public {
        uint256 existingGelatoBalance = GELATO.balance;
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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

    /*//////////////////////////////////////////////////////////////
                  EXECUTING CONDITIONAL ORDERS: LIMIT
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Limit_Valid_Margin() external {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD * 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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

    function test_ExecuteConditionalOrder_Limit_Valid_State() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD * 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        assert(conditionalOrder.priceImpactDelta == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ExecuteConditionalOrder_Limit_Valid_Synthetix() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD * 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        // confirm delayed order details are non-zero
        assert(order.isOffchain == true);
        assert(order.sizeDelta == 1 ether);
        assert(order.priceImpactDelta == PRICE_IMPACT_DELTA);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit != 0);
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                   EXECUTING CONDITIONAL ORDERS: STOP
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteConditionalOrder_Stop_Valid_Margin() external {
        uint256 preCommittedMargin = account.committedMargin();
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD / 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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

    function test_ExecuteConditionalOrder_Stop_Valid_State() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD / 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        assert(conditionalOrder.priceImpactDelta == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ExecuteConditionalOrder_Stop_Valid_Synthetix() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD / 2,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.STOP,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        // confirm delayed order details are non-zero
        assert(order.isOffchain == true);
        assert(order.sizeDelta == 1 ether);
        assert(order.priceImpactDelta == PRICE_IMPACT_DELTA);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit != 0);
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*//////////////////////////////////////////////////////////////
                              REDUCE ONLY
    //////////////////////////////////////////////////////////////*/

    function test_ReduceOnlyOrder_Valid_State() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(currentEthPriceInUSD);
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: -(1 ether / 2),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: true
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
        assert(conditionalOrder.priceImpactDelta == 0);
        assert(!conditionalOrder.reduceOnly);
    }

    function test_ReduceOnlyOrder_Valid_Synthetix() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(currentEthPriceInUSD);
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: -(1 ether / 2),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: true
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
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        // expect all details to be unset
        assert(order.isOffchain == true);
        assert(order.sizeDelta != 0);
        assert(order.priceImpactDelta != 0);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit != 0);
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    function test_ReduceOnlyOrder_Valid_Long(int256 fuzzedSizeDelta) external {
        vm.assume(fuzzedSizeDelta != 0);
        submitAtomicOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            priceImpactDelta: 1 ether / 2
        });
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
        assert(position.size == 1 ether); // sanity check :D
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: fuzzedSizeDelta,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        if (fuzzedSizeDelta > 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
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

    function test_ReduceOnlyOrder_Valid_Short(int256 fuzzedSizeDelta) external {
        vm.assume(fuzzedSizeDelta != 0);
        submitAtomicOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: -1 ether,
            priceImpactDelta: 1 ether / 2
        });
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
        assert(position.size == -1 ether); // sanity check :D
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: fuzzedSizeDelta,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: true
        });
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);
        if (fuzzedSizeDelta < 0) {
            // same sign thus not reduce only
            vm.expectEmit(true, true, true, true);
            emit ConditionalOrderCancelled(
                address(account),
                conditionalOrderId,
                IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
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
    function test_ConditionalOrder_Limit_Valid_Execute_Cancel() external {
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
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
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.priceImpactDelta == 0);
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
        ISynth synthsUSD = ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    function createAccount() private returns (Account account) {
        account = Account(payable(factory.newAccount()));
    }

    function createAccountAndDepositSUSD(uint256 amount) private returns (Account) {
        account = createAccount();
        mintSUSD(address(this), amount);
        sUSD.approve(address(account), amount);
        account.deposit(amount);
        vm.deal(address(account), 1 ether);
        return account;
    }

    function getMarketAddressFromKey(bytes32 key) private view returns (address market) {
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress("FuturesMarketManager")
                ).marketForKey(key)
            )
        );
    }

    function generateGelatoModuleData(uint256 conditionalOrderId)
        internal
        pure
        returns (bytes memory executionData, IOps.ModuleData memory moduleData)
    {
        IOps.Module[] memory modules = new IOps.Module[](1);
        modules[0] = IOps.Module.RESOLVER;
        bytes[] memory args = new bytes[](1);
        args[0] = abi.encodeWithSelector(IAccount.checker.selector, conditionalOrderId);
        moduleData = IOps.ModuleData({modules: modules, args: args});
        executionData =
            abi.encodeWithSelector(IAccount.executeConditionalOrder.selector, conditionalOrderId);
    }

    function submitAtomicOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 priceImpactDelta
    ) private {
        address market = getMarketAddressFromKey(marketKey);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
    }
}
