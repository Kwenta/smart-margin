// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "./utils/AccountExposed.sol";
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

contract AccountTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    uint256 private constant MAX_BPS = 10_000;
    bytes32 private constant TRACKING_CODE = "KWENTA";
    uint256 private constant AMOUNT = 10_000 ether;
    address private constant KWENTA_TREASURY = 0x82d2242257115351899894eF384f779b5ba8c695;
    address private constant FUTURES_MARKET_MANAGER = 0xdb89f3fc45A707Dd49781495f77f8ae69bF5cA6e;
    address public constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;

    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    uint256 private TRADE_FEE = 1;
    uint256 private LIMIT_ORDER_FEE = 2;
    uint256 private STOP_ORDER_FEE = 3;

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
    event ConditionalOrderCancelled(address indexed account, uint256 conditionalOrderId);
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

        sUSD = ERC20(ADDRESS_RESOLVER.getAddress("ProxyERC20sUSD"));

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
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        account.deposit(AMOUNT);
        assertEq(account.freeMargin(), AMOUNT);
        account.withdraw(AMOUNT);
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
        address issuer = ADDRESS_RESOLVER.getAddress("Issuer");
        ISynth synthsUSD = ISynth(ADDRESS_RESOLVER.getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return Account account
    function createAccountAndDepositSUSD() private returns (Account) {
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        account.deposit(AMOUNT);

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
}
