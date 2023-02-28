// SPDX-License-Identifier: UNLICENSED
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
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

contract AccountTest is Test, ConsolidatedEvents {
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

    receive() external payable {}

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        sUSD = ERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress("ProxyERC20sUSD"));
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
        account = Account(payable(factory.newAccount()));
        accountExposed = new AccountExposed();
        accountExposed.setSettings(settings);
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));
        currentEthPriceInUSD = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(accountExposed.expose_getPerpsV2Market(sETHPERP))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_GetVerison() external view {
        assert(account.VERSION() == "2.0.0");
    }

    function test_GetFactory() external view {
        assert(account.factory() == factory);
    }

    function test_GetFuturesMarketManager() external view {
        assert(account.futuresMarketManager() == IFuturesMarketManager(FUTURES_MARKET_MANAGER));
    }

    function test_GetSettings() external view {
        assert(account.settings() == settings);
    }

    function test_GetEvents() external view {
        assert(account.events() == events);
    }

    function test_GetCommittedMargin() external view {
        assert(account.committedMargin() == 0);
    }

    function test_GetConditionalOrderId() external view {
        assert(account.conditionalOrderId() == 0);
    }

    function test_GetDelayedOrder_EthMarket() external {
        IPerpsV2MarketConsolidated.DelayedOrder memory delayedOrder =
            account.getDelayedOrder({_marketKey: sETHPERP});
        assertEq(delayedOrder.isOffchain, false);
        assertEq(delayedOrder.sizeDelta, 0);
        assertEq(delayedOrder.priceImpactDelta, 0);
        assertEq(delayedOrder.targetRoundId, 0);
        assertEq(delayedOrder.commitDeposit, 0);
        assertEq(delayedOrder.keeperDeposit, 0);
        assertEq(delayedOrder.executableAtTime, 0);
        assertEq(delayedOrder.intentionTime, 0);
        assertEq(delayedOrder.trackingCode, "");
    }

    function test_GetDelayedOrder_InvalidMarket() external {
        vm.expectRevert();
        account.getDelayedOrder({_marketKey: "unknown"});
    }

    function test_Checker() external {
        vm.expectRevert();
        account.checker({_conditionalOrderId: 0});
    }

    function test_GetFreeMargin() external {
        assertEq(account.freeMargin(), 0);
    }

    function test_GetPosition_EthMarket() external {
        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition({_marketKey: sETHPERP});
        assertEq(position.id, 0);
        assertEq(position.lastFundingIndex, 0);
        assertEq(position.margin, 0);
        assertEq(position.lastPrice, 0);
        assertEq(position.size, 0);
    }

    function test_GetPosition_InvalidMarket() external {
        vm.expectRevert();
        account.getPosition({_marketKey: "unknown"});
    }

    function test_GetConditionalOrder() external {
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
        assertEq(conditionalOrder.priceImpactDelta, 0);
        assertEq(conditionalOrder.reduceOnly, false);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Margin_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert("UNAUTHORIZED");
        account.deposit(AMOUNT);
    }

    function test_Withdraw_Margin_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert("UNAUTHORIZED");
        account.withdraw(AMOUNT);
    }

    function test_Deposit_ETH_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert("UNAUTHORIZED");
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
    }

    function test_Withdraw_ETH_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert("UNAUTHORIZED");
        account.withdrawEth(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             FEE UTILITIES
    //////////////////////////////////////////////////////////////*/

    function test_CalculateTradeFee_EthMarket(int128 fuzzedSizeDelta) external {
        uint256 conditionalOrderFee = MAX_BPS / 99;
        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));
        uint256 percentToTake = settings.tradeFee() + conditionalOrderFee;
        uint256 fee = (accountExposed.expose_abs(int256(fuzzedSizeDelta)) * percentToTake) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;
        uint256 actualFee = accountExposed.expose_calculateTradeFee({
            _sizeDelta: fuzzedSizeDelta,
            _market: market,
            _conditionalOrderFee: conditionalOrderFee
        });
        assertEq(actualFee, feeInSUSD);
    }

    function test_CalculateTradeFee_InvalidMarket() external {
        int256 sizeDelta = -1 ether;
        vm.expectRevert();
        accountExposed.expose_calculateTradeFee({
            _sizeDelta: sizeDelta,
            _market: IPerpsV2MarketConsolidated(address(0)),
            _conditionalOrderFee: LIMIT_ORDER_FEE
        });
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

    function getMarketAddressFromKey(bytes32 key) private view returns (address market) {
        // market and order related params
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress("FuturesMarketManager")
                ).marketForKey(key)
            )
        );
    }
}
