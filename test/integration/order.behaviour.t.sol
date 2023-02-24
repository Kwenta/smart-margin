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
    ERC20 private sUSD;
    AccountExposed private accountExposed;

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

        // deploy contract that exposes Account's internal functions
        accountExposed = new AccountExposed();
        accountExposed.setSettings(settings);
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           CONDITIONAL ORDERS
    //////////////////////////////////////////////////////////////*/

    function testPlaceConditionalOrder() external {
        uint256 expectConditionalOrderId = 0;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // fetch ETH amount in sUSD
        uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );

        // expect ConditionalOrderPlaced event on calling placeConditionalOrder
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            address(account),
            expectConditionalOrderId,
            sETHPERP,
            int256(currentEthPriceInUSD),
            int256(currentEthPriceInUSD),
            currentEthPriceInUSD,
            IAccount.ConditionalOrderTypes.LIMIT,
            PRICE_IMPACT_DELTA,
            false
            );

        // submit conditional order (limit order) to Gelato
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: int256(currentEthPriceInUSD),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });
        assert(expectConditionalOrderId == conditionalOrderId);

        // check order was registered internally
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assert(conditionalOrder.marketKey == sETHPERP);
        assert(conditionalOrder.marginDelta == int256(currentEthPriceInUSD));
        assert(conditionalOrder.sizeDelta == int256(currentEthPriceInUSD));
        assert(conditionalOrder.targetPrice == currentEthPriceInUSD);
        assert(
            uint256(conditionalOrder.conditionalOrderType)
                == uint256(IAccount.ConditionalOrderTypes.LIMIT)
        );
        assert(conditionalOrder.gelatoTaskId != 0); // this is set by Gelato
        assert(conditionalOrder.priceImpactDelta == PRICE_IMPACT_DELTA);
        assert(!conditionalOrder.reduceOnly);
    }

    function testCancelConditionalOrder() external {
        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // fetch ETH amount in sUSD
        uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );

        // submit conditional order (limit order) to Gelato
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: int256(currentEthPriceInUSD),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });

        // expect ConditionalOrderCancelled event on calling cancelConditionalOrder
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            address(account),
            conditionalOrderId,
            IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER
            );

        // attempt to cancel order
        account.cancelConditionalOrder(conditionalOrderId);

        // check order was cancelled internally
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

    function testExecuteConditionalOrderAsGelato() external {
        IOps ops = IOps(OPS);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // fetch ETH amount in sUSD
        uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );

        // submit conditional order (limit order) to Gelato
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });

        // create Gelato module data
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // prank Gelato call to {IOps.exec}
        vm.prank(GELATO);
        ops.exec({
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

    function testCancelDelayedOrderSubmittedByGelato() external {
        IOps ops = IOps(OPS);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // fetch ETH amount in sUSD
        uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );

        // submit conditional order (limit order) to Gelato
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: false
        });

        // create Gelato module data
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // prank Gelato call to {IOps.exec}
        vm.prank(GELATO);
        ops.exec({
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

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);

        // expect all details to be unset
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
                             DELAYED ORDERS
    //////////////////////////////////////////////////////////////*/

    function testExecuteDelayedConditionalOrderAsGelato() external {
        IOps ops = IOps(OPS);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // fetch ETH amount in sUSD
        uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );

        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(currentEthPriceInUSD);
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // define commands to deposit margin and submit atomic order
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs to deposit margin and submit atomic order
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // submit conditional order (limit order) to Gelato that is reduced only
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: 0,
            _sizeDelta: -(1 ether / 2),
            _targetPrice: currentEthPriceInUSD,
            _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            _priceImpactDelta: PRICE_IMPACT_DELTA,
            _reduceOnly: true
        });

        // create Gelato module data
        (bytes memory executionData, IOps.ModuleData memory moduleData) =
            generateGelatoModuleData(conditionalOrderId);

        // mock Gelato call to {IOps.exec}
        vm.prank(GELATO);
        ops.exec({
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

    // function testReduceOnlyConditionalOrder(int fuzzedSizeDelta) external {
    //     IOps ops = IOps(OPS);

    //     // get account for trading
    //     Account account = createAccountAndDepositSUSD(AMOUNT);

    //     // fetch ETH amount in sUSD
    //     uint256 currentEthPriceInUSD = accountExposed.expose_sUSDRate(
    //         IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
    //     );

    //     // market and order related params
    //     address market = getMarketAddressFromKey(sETHPERP);
    //     int256 marginDelta = int256(currentEthPriceInUSD);
    //     int256 sizeDelta = 1 ether;
    //     uint256 priceImpactDelta = 1 ether / 2;

    //     // define commands to deposit margin and submit atomic order
    //     IAccount.Command[] memory commands = new IAccount.Command[](2);
    //     commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
    //     commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

    //     // define inputs to deposit margin and submit atomic order
    //     bytes[] memory inputs = new bytes[](2);
    //     inputs[0] = abi.encode(market, marginDelta);
    //     inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

    //     // call execute
    //     account.execute(commands, inputs);

    //     // get position details
    //     IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);

    //     if (fuzzedSizeDelta == 0) vm.expectRevert();

    //     // submit conditional order (limit order) to Gelato that is reduced only
    //     uint256 conditionalOrderId = account.placeConditionalOrder({
    //         _marketKey: sETHPERP,
    //         _marginDelta: 0,
    //         _sizeDelta: fuzzedSizeDelta,
    //         _targetPrice: currentEthPriceInUSD,
    //         _conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
    //         _priceImpactDelta: PRICE_IMPACT_DELTA,
    //         _reduceOnly: true
    //     });

    //     // create Gelato module data
    //     (bytes memory executionData, IOps.ModuleData memory moduleData) =
    //         generateGelatoModuleData(conditionalOrderId);

    //     if (fuzzedSizeDelta > 0) {
    //         vm.expectRevert();
    //     } else if (fuzzedSizeDelta <= 0) {
    //         if (fuzzedSizeDelta + position.size < 0) {
    //             vm.expectRevert();
    //         }
    //     }

    //     vm.prank(GELATO);
    //     ops.exec({
    //         taskCreator: address(account),
    //         execAddress: address(account),
    //         execData: executionData,
    //         moduleData: moduleData,
    //         txFee: GELATO_FEE,
    //         feeToken: ETH,
    //         useTaskTreasuryFunds: false,
    //         revertOnFailure: true
    //     });
    // }

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
        Account account = createAccount();
        mintSUSD(address(this), amount);
        sUSD.approve(address(account), amount);
        account.deposit(amount);
        (bool sent, bytes memory data) = address(account).call{value: 1 ether}("");
        assert(sent && data.length == 0);
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
}
