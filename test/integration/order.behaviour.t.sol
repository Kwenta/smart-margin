// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "../unit/utils/AccountExposed.sol";
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

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract OrderBehaviorTest is Test {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    /// @notice max BPS; used for decimals calculations
    uint256 private constant MAX_BPS = 10_000;

    // tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    // test amount used throughout tests
    uint256 private constant AMOUNT = 10_000 ether;

    // test price impact delta used throughout tests
    uint128 private constant PRICE_IMPACT_DELTA = 1 ether / 2;

    // test fee Gelato will charge for filling conditional orders
    uint256 private constant GELATO_FEE = 69;

    // synthetix (ReadProxyAddressResolver)
    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    // synthetix (FuturesMarketManager)
    address private constant FUTURES_MARKET_MANAGER = 0xdb89f3fc45A707Dd49781495f77f8ae69bF5cA6e;

    // Gelato
    address public constant GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;
    address public constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;
    address private constant OPS_PROXY_FACTORY = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // kwenta treasury multisig
    address private constant KWENTA_TREASURY = 0x82d2242257115351899894eF384f779b5ba8c695;

    // fee settings
    uint256 private tradeFee = 1;
    uint256 private limitOrderFee = 2;
    uint256 private stopOrderFee = 3;

    // Synthetix PerpsV2 market key(s)
    bytes32 private constant sETHPERP = "sETHPERP";
    bytes32 private constant sBTCPERP = "sBTCPERP";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, address indexed account, uint256 amount);
    event Withdraw(address indexed user, address indexed account, uint256 amount);
    event EthWithdraw(address indexed user, address indexed account, uint256 amount);
    event ConditionalOrderPlaced(
        address indexed account,
        uint256 conditionalOrderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    );
    event ConditionalOrderCancelled(
        address indexed account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    );
    event ConditionalOrderFilled(
        address indexed account, uint256 conditionalOrderId, uint256 fillPrice, uint256 keeperFee
    );
    event FeeImposed(address indexed account, uint256 amount);

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

    /// @notice Important to keep in mind that all test functions are isolated,
    /// meaning each test function is executed with a copy of the state after
    /// setUp and is executed in its own stand-alone EVM.
    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // establish sUSD address
        sUSD = ERC20(ADDRESS_RESOLVER.getAddress("ProxyERC20sUSD"));

        // uses deployment script for tests (2 birds 1 stone)
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: tradeFee,
            limitOrderFee: limitOrderFee,
            stopOrderFee: stopOrderFee
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

        // submit conditional order (limit order) to Gelato that is reduced only
        uint256 conditionalOrderId = account.placeConditionalOrder({
            _marketKey: sETHPERP,
            _marginDelta: int256(currentEthPriceInUSD),
            _sizeDelta: 1 ether,
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
        assert(conditionalOrder.reduceOnly);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // @HELPER
    /// @notice mint sUSD and transfer to address specified
    /// @dev Issuer.sol is an auxiliary helper contract that performs
    /// the issuing and burning functionality.
    /// Synth.sol is the base ERC20 token contract comprising most of
    /// the behaviour of all synths.
    /// Issuer is considered an "internal contract" therefore,
    /// it is permitted to call Synth.issue() which is restricted by
    /// the onlyInternalContracts modifier. Synth.issue() updates the
    /// token state (i.e. balance and total existing tokens) which effectively
    /// can be used to "mint" an account the underlying synth.
    /// @param to: address to mint and transfer sUSD to
    /// @param amount: amount to mint and transfer
    function mintSUSD(address to, uint256 amount) private {
        // fetch addresses needed
        address issuer = ADDRESS_RESOLVER.getAddress("Issuer");
        ISynth synthsUSD = ISynth(ADDRESS_RESOLVER.getAddress("SynthsUSD"));

        // set caller as issuer
        vm.prank(issuer);

        // mint sUSD
        synthsUSD.issue(to, amount);
    }

    // @HELPER
    /// @notice create margin base account
    /// @return account
    function createAccount() private returns (Account account) {
        // call factory to create account
        account = Account(payable(factory.newAccount()));
    }

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return Account account
    function createAccountAndDepositSUSD(uint256 amount) private returns (Account) {
        // call factory to create account
        Account account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), amount);

        // approve account to spend amount
        sUSD.approve(address(account), amount);

        // deposit sUSD into account
        account.deposit(amount);

        // send account eth for gas/trading
        (bool sent, bytes memory data) = address(account).call{value: 1 ether}("");
        assert(sent);
        assert(data.length == 0);

        return account;
    }

    // @HELPER
    /// @notice get address of market
    /// @return market address
    function getMarketAddressFromKey(bytes32 key) private view returns (address market) {
        // market and order related params
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(ADDRESS_RESOLVER.getAddress("FuturesMarketManager"))
                    .marketForKey(key)
            )
        );
    }

    // @HELPER
    /// @notice get data needed for pranking Gelato calls to executeConditionalOrder
    /// @return executionData needed to call executeConditionalOrder
    /// @return moduleData needed to call Gelato's exec
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
