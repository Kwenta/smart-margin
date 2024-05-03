// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {Setup} from "script/Deploy.s.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {Settings} from "src/Settings.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {AccountExposed} from "test/utils/AccountExposed.sol";
import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";
import {IFuturesMarketManager} from
    "src/interfaces/synthetix/IFuturesMarketManager.sol";
import {IPerpsV2MarketConsolidated} from "src/interfaces/IAccount.sol";
import {IPerpsV2ExchangeRate} from
    "src/interfaces/synthetix/IPerpsV2ExchangeRate.sol";

import {
    ADDRESS_RESOLVER,
    AMOUNT,
    BLOCK_NUMBER,
    FUTURES_MARKET_MANAGER,
    GELATO,
    OPS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    sETHPERP,
    SYSTEM_STATUS,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER
} from "test/utils/Constants.sol";

contract OrderFlowFeeTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Account private account;
    Settings private settings;

    // helper contracts for testing
    IERC20 private sUSD;
    AccountExposed private accountExposed;

    // constants
    uint256 private constant INITIAL_ORDER_FLOW_FEE = 5; // 0.005%

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

        // deploy an Account contract
        account = Account(payable(factory.newAccount()));

        // define helper contracts
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        sUSD = IERC20(addressResolver.getAddress(PROXY_SUSD));
        address futuresMarketManager =
            addressResolver.getAddress(FUTURES_MARKET_MANAGER);
        address systemStatus = addressResolver.getAddress(SYSTEM_STATUS);
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
            systemStatus,
            GELATO,
            OPS,
            address(settings),
            UNISWAP_UNIVERSAL_ROUTER,
            UNISWAP_PERMIT2
        );
        accountExposed = new AccountExposed(params);

        // call approve() on an ERC20 to grant an infinite allowance to the SM account contract
        sUSD.approve(address(account), type(uint256).max);

        // set the order flow fee to a non-zero value
        settings.setOrderFlowFee(INITIAL_ORDER_FLOW_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// Verifies that Order Flow Fee is correctly calculated
    /// For this test, it is assumed that there is enough account margin to cover fee
    function test_calculateOrderFlowFee(uint256 fee) public {
        vm.assume(fee < settings.MAX_ORDER_FLOW_FEE());
        settings.setOrderFlowFee(fee);

        fundAccount(AMOUNT);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        (uint256 sUSDmarketRate, uint256 imposedOrderFlowFee) =
            account.getExpectedOrderFlowFee(market, sizeDelta);

        if (fee == 0) {
            assertEq(imposedOrderFlowFee, 0);
        } else {
            uint256 orderFlowFeeMath = abs(sizeDelta) * sUSDmarketRate
                * settings.orderFlowFee() / settings.MAX_ORDER_FLOW_FEE();
            assertEq(orderFlowFeeMath, imposedOrderFlowFee);
        }
    }

    /// Verifies that OrderFlowFee is correctly sent from account margin when there is enough funds to cover orderFlowFee
    function test_imposeOrderFlowFee_account_margin() public {
        fundAccount(AMOUNT);
        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        /// inital funding - sETHPERP margin = 8000 ether
        uint256 accountMarginBeforeFee = AMOUNT - uint256(marginDelta);

        (, uint256 imposedFee) =
            account.getExpectedOrderFlowFee(market, sizeDelta);

        assertEq(accountMarginBeforeFee - imposedFee, account.freeMargin());
    }

    /// Verifies that OrderFlowFee is correctly sent from market margin when there is no funds to cover orderFlowFee in account margin
    function test_imposeOrderFlowFee_market_margin() public {
        fundAccount(AMOUNT);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Deposit all margin so that account has no margin to cover orderFlowFee
        int256 marginDelta = int256(AMOUNT);
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        (, uint256 imposedFee) =
            account.getExpectedOrderFlowFee(market, position.size);

        assertEq(uint256(position.margin), AMOUNT - imposedFee - 563);
    }

    /// Verifies that OrderFlowFee is correctly sent from both market margin and account margin when there is not enough funds to cover orderFlowFee in account margin
    function test_imposeOrderFlowFee_both_margin() public {
        fundAccount(AMOUNT);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Leave 10_000 in account (not enough to cover fees)
        int256 marginDelta = int256(AMOUNT) - 10_000;
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        (, uint256 imposedFee) =
            account.getExpectedOrderFlowFee(market, position.size);

        // Account margin is emptied
        assertEq(account.freeMargin(), 0);

        // Market margin is reduced by (imposedFee - 10 000)
        assertEq(
            uint256(position.margin),
            uint256(marginDelta) - (imposedFee - 10_000) - 563
        );
    }

    /// @custom:todo use atomic order flow to simplify testing
    /// Synthetix makes modify position (which is called if there is not enough account margin
    /// Reverts if the resulting position is too large, outside the max leverage, or is liquidating.
    function test_imposeOrderFlowFee_market_margin_failed() public {
        /// @custom:todo test the following assuming the account
        /// has insufficient margin and the market has insufficient margin
        /// (i.e., withdrawing from the market fails due to outstanding position or
        /// order exceeding allowed leverage if margin is taken):
        /// 1. error is caught for each scenario where the market margin is insufficient
        //
    }

    /// Verifies that the correct Event is emitted with correct value
    function test_imposeOrderFlowFee_event() public {
        /// @custom:todo test the following:

        fundAccount(AMOUNT);
        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        vm.expectEmit(true, true, true, true);
        // orderFlowFee is 94025250000000000 in this configuration
        emit OrderFlowFeeImposed(address(account), 94_025_250_000_000_000);

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);
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

    function abs(int256 x) private pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
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
}
