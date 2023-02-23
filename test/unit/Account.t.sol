// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "./utils/AccountExposed.sol";
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
import {ISynth} from "@synthetix/ISynth.sol";
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

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

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

        account = Account(payable(factory.newAccount()));

        // deploy contract that exposes Account's internal functions
        accountExposed = new AccountExposed();
        accountExposed.setSettings(settings);
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function testGetVerison() external view {
        assert(account.VERSION() == "2.0.0");
    }

    function testGetFactory() external view {
        assert(account.factory() == factory);
    }

    function testGetFuturesMarketManager() external view {
        assert(account.futuresMarketManager() == IFuturesMarketManager(FUTURES_MARKET_MANAGER));
    }

    function testGetSettings() external view {
        assert(account.settings() == settings);
    }

    function testGetEvents() external view {
        assert(account.events() == events);
    }

    function testGetCommittedMargin() external view {
        assert(account.committedMargin() == 0);
    }

    function testGetConditionalOrderId() external view {
        assert(account.conditionalOrderId() == 0);
    }

    function testGetDelayedOrderInEthMarket() external {
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

    function testGetDelayedOrderInInvalidMarket() external {
        vm.expectRevert();
        account.getDelayedOrder({_marketKey: "unknown"});
    }

    function testChecker() external {
        // if no order exists, call reverts
        vm.expectRevert();
        account.checker({_conditionalOrderId: 0});
    }

    function testCanFetchFreeMargin() external {
        assertEq(account.freeMargin(), 0);
    }

    function testGetPositionInEthMarket() external {
        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition({_marketKey: sETHPERP});
        assertEq(position.id, 0);
        assertEq(position.lastFundingIndex, 0);
        assertEq(position.margin, 0);
        assertEq(position.lastPrice, 0);
        assertEq(position.size, 0);
    }

    function testPositionInInvalidMarket() external {
        // if no market with that _marketKey exists, call reverts
        vm.expectRevert();
        account.getPosition({_marketKey: "unknown"});
    }

    function getConditionalOrder() external {
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

    function testOnlyOwnerCanDepositSUSD() external {
        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // deposit sUSD into account
        vm.expectRevert("UNAUTHORIZED");
        account.deposit(AMOUNT);
    }

    function testOnlyOwnerCanWithdrawSUSD() external {
        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // attempt to withdraw sUSD from account
        vm.expectRevert("UNAUTHORIZED");
        account.withdraw(AMOUNT);
    }

    function testOnlyOwnerCanDepositETH() external {
        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // attempt to deposit ETH into account
        vm.expectRevert("UNAUTHORIZED");
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
    }

    function testOnlyOwnerCanWithdrawETH() external {
        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // attempt to withdraw ETH
        vm.expectRevert("UNAUTHORIZED");
        account.withdrawEth(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             FEE UTILITIES
    //////////////////////////////////////////////////////////////*/

    function testCalculateTradeFeeInEthMarket(int128 fuzzedSizeDelta) external {
        // conditional order fee
        uint256 conditionalOrderFee = MAX_BPS / 99; // 1% fee

        // define market
        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));

        // calculate expected fee
        uint256 percentToTake = settings.tradeFee() + conditionalOrderFee;
        uint256 fee = (accountExposed.expose_abs(int256(fuzzedSizeDelta)) * percentToTake) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;

        // call calculateTradeFee()
        uint256 actualFee = accountExposed.expose_calculateTradeFee({
            _sizeDelta: fuzzedSizeDelta,
            _market: market,
            _conditionalOrderFee: conditionalOrderFee
        });

        assertEq(actualFee, feeInSUSD);
    }

    function testCalculateTradeFeeInInvalidMarket() external {
        int256 sizeDelta = -1 ether;

        // call reverts if market is invalid
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

    function testAbs(int256 x) public view {
        if (x == 0) {
            assert(accountExposed.expose_abs(x) == 0);
        } else {
            assert(accountExposed.expose_abs(x) > 0);
        }
    }

    function testIsSameSign(int256 x, int256 y) public {
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

    // @HELPER
    /// @notice get address of market
    /// @return market address
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
