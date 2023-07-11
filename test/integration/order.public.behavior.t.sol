// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Setup} from "script/Deploy.s.sol";

import {Account} from "src/Account.sol";
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

contract OrderPublicBehaviorTest is Test, ConsolidatedEvents {
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

    // conditional order variables
    uint256 conditionalOrderId;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        Setup setup = new Setup();

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

        account = Account(payable(factory.newAccount()));

        (currentEthPriceInUSD,) = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(
                accountExposed.expose_getPerpsV2Market(sETHPERP)
            )
        );

        PERMIT2 = IPermit2(UNISWAP_PERMIT2);
        sUSD.approve(UNISWAP_PERMIT2, type(uint256).max);
        PERMIT2.approve(
            address(sUSD), address(account), type(uint160).max, type(uint48).max
        );

        fundAccount(AMOUNT);

        conditionalOrderId = placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(currentEthPriceInUSD),
            sizeDelta: 1 ether,
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_ExecuteConditionalOrder() public {
        account.executeConditionalOrder(conditionalOrderId);
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder(conditionalOrderId);
        assertEq(conditionalOrder.sizeDelta, 0);
    }

    function test_UpdatePythPrice() public {
        /// @custom:todo will likely need to mock
    }

    function test_PayExecutorFee() public {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrderWithPriceUpdate() public {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrderWithPriceUpdate_Executor_Fee()
        public
    {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrderWithPriceUpdate_Pyth_Updated()
        public
    {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrderWithPriceUpdate_Pyth_Fee() public {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrderWithPriceUpdate_Invalid_PriceFeed()
        public
    {
        /// @custom:todo
    }

    function test_ExecuteConditionalOrder_Invalid_ConditionalOrder() public {
        /// @custom:todo
        // expect -> CannotExecuteConditionalOrder Custom Error
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

    function modifyAccountMargin(int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
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
}
