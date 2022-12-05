// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/interfaces/IFuturesMarket.sol";
import "../../contracts/interfaces/IFuturesMarketManager.sol";
import "../../contracts/interfaces/IAddressResolver.sol";
import "../../contracts/interfaces/IMarginBaseTypes.sol";
import "../../contracts/MarginBaseSettings.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "./utils/MintableERC20.sol";

contract MarginBaseTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 private marginAsset;
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;
    MarginBase private account;

    // test address
    address private nonOwnerEOA = 0x6e1768574dC439aE6ffCd2b0A0f218105f2612c6;

    // market keys
    bytes32 private constant ETH_MARKET_KEY = "sETH";
    bytes32 private constant BTC_MARKET_KEY = "sBTC";
    bytes32 private constant LINK_MARKET_KEY = "sLINK";
    bytes32 private constant UNI_MARKET_KEY = "sUNI";

    // settings
    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    uint256 private constant TRADE_FEE = 5; // 5 BPS
    uint256 private constant LIMIT_ORDER_FEE = 5; // 5 BPS
    uint256 private constant STOP_LOSS_FEE = 10; // 10 BPS

    /// @notice max BPS
    uint256 private constant MAX_BPS = 10000;

    struct Position {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        MarginBase.OrderTypes orderType
    );

    event OrderCancelled(address indexed account, uint256 orderId);

    event OrderFilled(
        address indexed account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    );

    event FeeImposed(address indexed account, uint256 amount);

    // futures market(s) for mocking: addresses match those on OE Mainnet
    IFuturesMarket private futuresMarketETH =
        IFuturesMarket(0xf86048DFf23cF130107dfB4e6386f574231a5C65);
    IFuturesMarket private futuresMarketBTC =
        IFuturesMarket(0xEe8804d8Ad10b0C3aD1Bd57AC3737242aD24bB95);
    IFuturesMarket private futuresMarketLINK =
        IFuturesMarket(0x1228c7D8BBc5bC53DB181bD7B1fcE765aa83bF8A);
    IFuturesMarket private futuresMarketUNI =
        IFuturesMarket(0x5Af0072617F7f2AEB0e314e2faD1DE0231Ba97cD);

    // futures market manager for mocking
    IFuturesMarketManager private futuresManager =
        IFuturesMarketManager(0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B);
    // address resolver for mocking
    IAddressResolver private addressResolver =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);
    // exchanger (from L2) used primarily for mocking
    IExchanger private exchanger =
        IExchanger(0xC37c47C55d894443493c1e2E615f4F9f4b8fDEa4);
    // kwenta treasury address on OE Mainnet
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    IOps private gelatoOps = IOps(0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c);
    address private gelato = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;

    /*///////////////////////////////////////////////////////////////
                                Mocking
    ///////////////////////////////////////////////////////////////*/

    /**
     * Mocking AddressResolver.sol
     *
     * @notice mock requireAndGetAddress (which returns futuresManager address)
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockAddressResolverCalls() internal {
        /*
         * Calls to mocked addresses may revert if there is no code on the address.
         * This is because Solidity inserts an extcodesize check before some contract calls.
         * To circumvent this, use the etch cheatcode if the mocked address has no code.
         */
        cheats.etch(address(addressResolver), new bytes(0x19));

        bytes32 futuresManagerKey = "FuturesMarketManager";
        bytes32 exchangerKey = "Exchanger";

        // @mock addressResolver.requireAndGetAddress()
        cheats.mockCall(
            address(addressResolver),
            abi.encodeWithSelector(
                IAddressResolver.requireAndGetAddress.selector,
                futuresManagerKey,
                "MarginBase: Could not get Futures Market Manager"
            ),
            abi.encode(address(futuresManager))
        );

        cheats.mockCall(
            address(addressResolver),
            abi.encodeWithSelector(
                IAddressResolver.requireAndGetAddress.selector,
                exchangerKey,
                "MarginBase: Could not get Exchanger"
            ),
            abi.encode(address(exchanger))
        );
    }

    /**
     * Mocking FuturesMarketManager.sol
     *
     * @notice loop through each market and mock respective functions
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockFuturesMarketManagerCalls() internal {
        // use the etch cheatcode if the mocked address has no code
        cheats.etch(address(futuresManager), new bytes(0x19));

        bytes32[4] memory keys = [
            ETH_MARKET_KEY,
            BTC_MARKET_KEY,
            LINK_MARKET_KEY,
            UNI_MARKET_KEY
        ];
        IFuturesMarket[4] memory marketsToMock = [
            futuresMarketETH,
            futuresMarketBTC,
            futuresMarketLINK,
            futuresMarketUNI
        ];
        for (uint16 i = 0; i < 4; i++) {
            // @mock futuresManager.marketForKey()
            cheats.mockCall(
                address(futuresManager),
                abi.encodeWithSelector(
                    IFuturesMarketManager.marketForKey.selector,
                    keys[i]
                ),
                abi.encode(address(marketsToMock[i]))
            );
        }
    }

    /**
     * Mocking FuturesMarket.sol
     *
     * @notice loop through each market and mock respective functions
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockFuturesMarketCalls() internal {
        bytes32 trackingCode = "KWENTA";

        IFuturesMarket[4] memory marketsToMock = [
            futuresMarketETH,
            futuresMarketBTC,
            futuresMarketLINK,
            futuresMarketUNI
        ];
        for (uint16 i = 0; i < 4; i++) {
            // use the etch cheatcode if the mocked address has no code
            cheats.etch(address(marketsToMock[i]), new bytes(0x19));

            // @mock market.transferMargin()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.transferMargin.selector,
                    1 ether
                ),
                abi.encode()
            );
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.transferMargin.selector,
                    -1 ether
                ),
                abi.encode()
            );

            // @mock market.modifyPositionWithTracking()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.modifyPositionWithTracking.selector,
                    1 ether,
                    trackingCode
                ),
                abi.encode()
            );
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.modifyPositionWithTracking.selector,
                    -1 ether,
                    trackingCode
                ),
                abi.encode()
            );

            // @mock market.positions()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.positions.selector,
                    address(account)
                ),
                abi.encode(Position(0, 0, 1 ether, 1 ether, 1 ether))
            );

            // @mock market.withdrawAllMargin()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.withdrawAllMargin.selector
                ),
                abi.encode()
            );

            // @mock market.closePosition()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(IFuturesMarket.closePosition.selector),
                abi.encode()
            );
        }
    }

    /**
     * Mocking sUSD Exchange Rate
     *
     * @param mockedMarket market to mock
     * @param mockedPrice price to return when assetPrice() called
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockExchangeRates(IFuturesMarket mockedMarket, uint256 mockedPrice)
        internal
    {
        cheats.mockCall(
            address(mockedMarket),
            abi.encodePacked(IFuturesMarket.baseAsset.selector),
            abi.encode("sSYNTH")
        );
        // @mock market.assetPrice()
        cheats.mockCall(
            address(mockedMarket),
            abi.encodeWithSelector(IFuturesMarket.assetPrice.selector),
            abi.encode(mockedPrice, false)
        );
    }

    function mockDynamicFee(
        IFuturesMarket mockedMarket,
        uint256 mockedFee,
        bool tooVolatile
    ) internal {
        cheats.mockCall(
            address(mockedMarket),
            abi.encodePacked(IFuturesMarket.baseAsset.selector),
            abi.encode("sETH")
        );
        cheats.mockCall(
            address(exchanger),
            abi.encodeWithSelector(
                IExchanger.dynamicFeeRateForExchange.selector
            ),
            abi.encode(mockedFee, tooVolatile)
        );
    }

    /**
     * Mocking MintableERC20.sol
     *
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockMarginBalance(uint256 amount) internal {
        cheats.mockCall(
            address(marginAsset),
            abi.encodePacked(IERC20.balanceOf.selector),
            abi.encode(amount)
        );
    }

    function mockGelato(uint256 fee) internal {
        // mock gelato fee details
        cheats.mockCall(
            account.ops(),
            abi.encodePacked(IOps.getFeeDetails.selector),
            abi.encode(fee, account.ETH())
        );

        // mock gelato address getter
        cheats.mockCall(
            account.ops(),
            abi.encodePacked(IOps.gelato.selector),
            abi.encode(gelato)
        );

        // mock gelato address getter
        cheats.mockCall(
            account.ops(),
            abi.encodePacked(IOps.cancelTask.selector),
            abi.encode(0)
        );
    }

    /*///////////////////////////////////////////////////////////////
                                Setup
    ///////////////////////////////////////////////////////////////*/

    /// @dev enable payments to this contract
    receive() external payable {}

    function setUp() public {
        mockAddressResolverCalls();

        marginBaseSettings = new MarginBaseSettings(
            KWENTA_TREASURY,
            TRADE_FEE,
            LIMIT_ORDER_FEE,
            STOP_LOSS_FEE
        );

        marginAsset = new MintableERC20(address(this), 0);

        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(marginAsset),
            address(addressResolver),
            address(marginBaseSettings),
            payable(address(gelatoOps))
        );
        account = MarginBase(marginAccountFactory.newAccount());

        mockFuturesMarketManagerCalls();
        mockFuturesMarketCalls();
    }

    function testOwnership() public {
        assertEq(account.owner(), address(this));
    }

    function testExpectedMargin() public {
        assertEq(address(account.marginAsset()), address(marginAsset));
    }

    /*///////////////////////////////////////////////////////////////
                                Helpers
    ///////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) internal {
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
    }

    function placeAdvancedOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IMarginBase.OrderTypes orderType
    ) internal returns (uint256 orderId) {
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        orderId = account.placeOrder(
            marketKey,
            marginDelta,
            sizeDelta,
            targetPrice,
            orderType
        );
    }

    function mockExchangeRatesForDistributionTests() internal {
        mockExchangeRates(futuresMarketETH, 1 ether);
        mockExchangeRates(futuresMarketBTC, 1 ether);
        mockExchangeRates(futuresMarketLINK, 1 ether);
        mockExchangeRates(futuresMarketUNI, 1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                                Utils
    ///////////////////////////////////////////////////////////////*/

    /// Enable mocking for high level function calls that don't return
    /// @dev Bypass the extcodesize check for non returning function calls
    /// https://github.com/ethereum/solidity/issues/12204
    /// https://book.getfoundry.sh/cheatcodes/mock-call.html#description
    function mockCall(address where, bytes memory data) internal {
        // Fill target with bytes
        cheats.etch(where, new bytes(0x19));
        // Mock target call
        cheats.mockCall(where, data, abi.encode());
    }

    function getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func)));
    }

    /*///////////////////////////////////////////////////////////////
                                Unit Tests
    ///////////////////////////////////////////////////////////////*/

    /********************************************************************
     * deposit()
     * withdraw()
     ********************************************************************/
    function testDeposit() public {
        uint256 amount = 10 ether;
        deposit(amount);
        assertEq(marginAsset.balanceOf(address(account)), (amount));
    }

    function testWithdrawal() public {
        uint256 amount = 10 ether;
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint256 amount) public {
        cheats.assume(amount > 0);
        cheats.assume(amount <= 10000000 ether); // 10_000_000
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    function testSendingEthToAccount() public payable {
        (bool success, ) = address(account).call{value: 1 ether}("");
        require(success, "call failed");
        assertEq(address(account).balance, 1 ether);
    }

    function testEthDepositWithdrawal() public payable {
        uint256 amount = 1 ether;
        cheats.deal(address(this), amount);

        // Deposit
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        account.placeOrder{value: amount}(
            ETH_MARKET_KEY,
            0,
            1,
            0,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // Withdraw
        account.withdrawEth(amount);
    }

    /********************************************************************
     * distributeMargin()
     ********************************************************************/
    function testDistributeMargin() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](4);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        newPositions[1] = IMarginBaseTypes.NewPosition({
            marketKey: BTC_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        newPositions[2] = IMarginBaseTypes.NewPosition({
            marketKey: LINK_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        newPositions[3] = IMarginBaseTypes.NewPosition({
            marketKey: UNI_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        account.distributeMargin(newPositions);
        //assertEq(account.getNumberOfInternalPositions(), 4);
    }

    /// @dev DistributeMargin fuzz test
    function testDistributeMargin(uint8 numberOfNewPositions) public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](
                numberOfNewPositions
            );

        for (uint8 i = 0; i < numberOfNewPositions; i++) {
            newPositions[i] = IMarginBaseTypes.NewPosition({
                marketKey: ETH_MARKET_KEY,
                marginDelta: 1 ether,
                sizeDelta: 1 ether
            });
        }

        account.distributeMargin(newPositions);
        // assertEq(
        //     account.getNumberOfInternalPositions(),
        //     (numberOfNewPositions == 0 ? 0 : 1)
        // );
    }

    function testCannotDistributeMarginWithInvalidKey() public {
        mockExchangeRatesForDistributionTests();

        bytes32 key = "LUNA";
        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: key,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        cheats.expectRevert();
        account.distributeMargin(newPositions);
    }

    /********************************************************************
     * depositAndDistribute()
     ********************************************************************/
    function testDepositAndDistribute() public {
        uint256 amount = 5 ether;
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](2);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });
        newPositions[1] = IMarginBaseTypes.NewPosition({
            marketKey: BTC_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });

        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);

        account.depositAndDistribute(amount, newPositions);
        //assertEq(account.getNumberOfInternalPositions(), 2);
    }

    function testCannotDepositAndDistributeAsNonOwner() public {
        uint256 amount = 5 ether;
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });

        marginAsset.mint(nonOwnerEOA, amount);
        marginAsset.approve(nonOwnerEOA, amount);

        cheats.expectRevert(
            abi.encodePacked("Ownable: caller is not the owner")
        );
        cheats.prank(nonOwnerEOA); // non-owner calling depositAndDistribute()
        account.depositAndDistribute(amount, newPositions);
    }

    /********************************************************************
     * position removed when liquidated
     ********************************************************************/
    // I encourage anyone reading this to walkthrough the function calls
    // via the command:  npm run f-test:unit -- -vvvvv
    function testLiquidatedPositionInDistributeMargin() public {
        deposit(2 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });

        // open position in ETH Market
        account.distributeMargin(newPositions);

        // mock liquidation
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // attempt to modify position
        /// @notice since sizeDelta is zero, and the position was liquidated
        /// we expect execution to fail (i.e. successfully handled liquidation)
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 0
        });

        // since position was liquidated, the modification will actually be
        // treated as a new position (i.e. will revert if size is zero)
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.ValueCannotBeZero.selector,
                bytes32("sizeDelta")
            )
        );
        account.distributeMargin(newPositions);
    }

    /********************************************************************
     * remove/exit position
     ********************************************************************/
    function testCanExitPosition() public {
        deposit(2 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: 1 ether
        });

        // open position in ETH Market
        account.distributeMargin(newPositions);

        newPositions[0] = IMarginBaseTypes.NewPosition({
            marketKey: ETH_MARKET_KEY,
            marginDelta: 1 ether,
            sizeDelta: -1 ether
        });

        account.distributeMargin(newPositions);

        // since second position size was the inverse of the first, execution of that trade stopped
        //assertEq(account.getNumberOfInternalPositions(), 0);
    }

    /********************************************************************
     * trade fees
     ********************************************************************/
    function testTradeFee() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](4);
        newPositions[0] = IMarginBaseTypes.NewPosition(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.NewPosition(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[2] = IMarginBaseTypes.NewPosition(
            LINK_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[3] = IMarginBaseTypes.NewPosition(
            UNI_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);

        /*
         * @dev mockExchangeRatesForDistributionTests()
         * results in the exchange rates for all baseAssets
         * being 1e18 (1 eth == 1 btc == 1 link == 1 uni == 1 usd)
         *
         * the purpose of these tests isnt ensuring exchange rates are correct.
         * the above mocking allows for isolated fee calculation tests
         *
         * If each trade size is 1 USD, then even 255 (max) trades would
         * result in less than 1 USD in fees (assuming tradeFee == 5)
         * so do not be alarmed:
         * ex:
         * (255 * 5) / 10_000 = 0.1275
         */

        uint256 totalSizeDelta = 4 * (1 ether);
        uint256 expectedFee = (totalSizeDelta * marginBaseSettings.tradeFee()) /
            MAX_BPS;

        assertEq(marginAsset.balanceOf(KWENTA_TREASURY), expectedFee);
    }

    function testTradeFeeMaxPositions() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](255);

        for (uint8 i = 0; i < 255; i++) {
            newPositions[i] = IMarginBaseTypes.NewPosition(
                ETH_MARKET_KEY,
                1 ether,
                1 ether
            );
        }

        account.distributeMargin(newPositions);

        /*
         * @dev mockExchangeRatesForDistributionTests()
         * results in the exchange rates for all baseAssets
         * being 1e18 (1 eth == 1 btc == 1 link == 1 uni == 1 usd)
         *
         * the purpose of these tests isnt ensuring exchange rates are correct.
         * the above mocking allows for isolated fee calculation tests
         *
         * If each trade size is 1 USD, then even 255 (max) trades would
         * result in less than 1 USD in fees (assuming tradeFee == 5)
         * so do not be alarmed:
         * ex:
         * (255 * 5) / 10_000 = 0.1275
         */

        uint256 totalSizeDelta = 255 * (1 ether);
        uint256 expectedFee = (totalSizeDelta * marginBaseSettings.tradeFee()) /
            MAX_BPS;

        assertEq(marginAsset.balanceOf(KWENTA_TREASURY), expectedFee);
    }

    /********************************************************************
     * sUSDRate()
     ********************************************************************/
    function testInvalidPrice() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        // update: @mock market.assetPrice()
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(IFuturesMarket.assetPrice.selector),
            abi.encode(ETH_MARKET_KEY, true) // invalid == true
        );

        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );

        marginAsset.mint(address(this), 1 ether);
        marginAsset.approve(address(account), 1 ether);

        cheats.expectRevert(
            abi.encodeWithSelector(MarginBase.InvalidPrice.selector)
        );
        account.depositAndDistribute(1 ether, newPositions);
    }

    /********************************************************************
     * Advanced Orders Logic
     ********************************************************************/

    function testLimitValidLongOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    function testLimitValidShortOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = -1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 4e18;

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    // either closing to stop loss (of a short) or opening to catch a breakout to the upside
    function testStopValidLongOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 3e18 + 1;

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.STOP
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    // either closing to stop loss or opening to catch a breakout to the downside
    function testStopValidShortOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = -1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 3e18 - 1;

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.STOP
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitValid(uint256 currentPrice) public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs greater than limit price
        cheats.assume(currentPrice <= expectedLimitPrice);

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitInvalid(uint256 currentPrice) public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs less than limit price
        cheats.assume(currentPrice > expectedLimitPrice);

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(!isValid);
    }

    /// @notice Tests the assumption that the order will always be executed at target price or worse
    /// @dev stop order logic fuzz test
    function testStopValid(uint256 currentPrice) public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 targetStopPrice = 3e18;

        // Toss out fuzz runs greater than target price
        cheats.assume(currentPrice >= targetStopPrice);

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            targetStopPrice,
            IMarginBaseTypes.OrderTypes.STOP
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    /// @notice Tests the assumption that the order will always be executed at target price or worse
    /// @dev stop order logic fuzz test
    function testStopInvalid(uint256 currentPrice) public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 targetStopPrice = 3e18;

        // Toss out fuzz runs less than target price
        cheats.assume(currentPrice < targetStopPrice);

        // Setup
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            targetStopPrice,
            IMarginBaseTypes.OrderTypes.STOP
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(!isValid);
    }

    function testMaxFeeExceeded() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 expectedMaxFee = 10; // 10 basis points
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        uint256 orderId = account.placeOrderWithFeeCap(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT,
            expectedMaxFee
        );

        mockDynamicFee(futuresMarketETH, 100, false);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(!isValid);
    }

    function testTooVolatile() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 expectedMaxFee = 10; // 10 basis points
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        uint256 orderId = account.placeOrderWithFeeCap(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT,
            expectedMaxFee
        );

        mockDynamicFee(futuresMarketETH, 0, true);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(!isValid);
    }

    function testMaxFeeValid() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;
        uint256 expectedMaxFee = 10; // 10 basis points
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        uint256 orderId = account.placeOrderWithFeeCap(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT,
            expectedMaxFee
        );

        mockDynamicFee(futuresMarketETH, 0, false);
        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    function testMaxFeeValidWhenEqual() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;
        uint256 expectedMaxFee = 10; // 10 basis points
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        uint256 orderId = account.placeOrderWithFeeCap(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT,
            expectedMaxFee
        );

        mockDynamicFee(futuresMarketETH, 10, false);
        mockExchangeRates(futuresMarketETH, currentPrice);
        (bool isValid, ) = account.validOrder(orderId);
        assertTrue(isValid);
    }

    /********************************************************************
     * Advanced Orders Placement
     ********************************************************************/

    function testPlaceOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        (, , , uint256 actualLimitPrice, , , ) = account.orders(orderId);
        assertEq(expectedLimitPrice, actualLimitPrice);
    }

    function testPlaceOrderWithFeeCap() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 expectedMaxFee = 10; // 10 basis points
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        uint256 orderId = account.placeOrderWithFeeCap(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT,
            expectedMaxFee
        );
        (, , , , , , uint256 maximumDynamicFee) = account.orders(orderId);
        assertEq(expectedMaxFee, maximumDynamicFee);
    }

    function testPlaceOrderWithInsufficientEth() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.InsufficientEthBalance.selector,
                0, // 0 ETH in account
                1 ether / 100 // .01 ETH minimum
            )
        );

        account.placeOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
    }

    /// @dev EVM reverts when using an order type that does not exist in the enum
    function testPlaceOrderWithInvalidOrderType() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        cheats.deal(address(account), 1 ether / 10);
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));

        // Bad Order
        (bool success, ) = address(account).call(
            abi.encodeWithSelector(
                account.placeOrder.selector,
                ETH_MARKET_KEY,
                int256(amount),
                orderSizeDelta,
                expectedLimitPrice,
                2
            )
        );
        assertTrue(!success);

        // Good Order
        (success, ) = address(account).call(
            abi.encodeWithSelector(
                account.placeOrder.selector,
                ETH_MARKET_KEY,
                int256(amount),
                orderSizeDelta,
                expectedLimitPrice,
                1
            )
        );
        assertTrue(success);
    }

    function testPlaceOrderWithZeroSize() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 0;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.ValueCannotBeZero.selector,
                bytes32("_sizeDelta")
            )
        );
        account.placeOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
    }

    function testPlaceOrderEmitsEvent() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);

        cheats.expectEmit(true, false, false, true, address(account));
        emit OrderPlaced(
            address(account),
            0, // first order
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
    }

    function testCommittingMargin() public {
        assertEq(account.committedMargin(), 0);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        assertEq(account.committedMargin(), amount);
    }

    // assert cannot withdraw committed margin
    function testWithdrawingCommittedMargin() public {
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);
        placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.InsufficientFreeMargin.selector,
                originalDeposit - amountToCommit,
                amountToCommit
            )
        );
        account.withdraw(originalDeposit);
    }

    function testWithdrawingCommittedMargin(uint256 originalDeposit) public {
        cheats.assume(originalDeposit > 0);
        assertEq(account.committedMargin(), 0);
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);

        // the maximum margin delta is positive 2^128 because it is int256
        cheats.assume(amountToCommit < 2**128 - 1);
        // this is a valid case (unless we want to restrict limit orders from not changing margin)
        cheats.assume(amountToCommit != 0);

        placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.InsufficientFreeMargin.selector,
                originalDeposit - amountToCommit,
                amountToCommit
            )
        );
        account.withdraw(originalDeposit);
    }

    // assert cannot use committed margin when opening new positions
    function testDistributingCommittedMargin() public {
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 firstOrderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);

        placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            firstOrderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        int256 secondOrderMarginDelta = 1e18;
        int256 secondOrderSizeDelta = 1e18;
        IMarginBaseTypes.NewPosition[]
            memory newPositions = new IMarginBaseTypes.NewPosition[](1);
        newPositions[0] = IMarginBaseTypes.NewPosition(
            "sETH",
            secondOrderMarginDelta,
            secondOrderSizeDelta
        );

        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.InsufficientFreeMargin.selector,
                originalDeposit - amountToCommit, // free margin
                secondOrderMarginDelta // amount attempting to use
            )
        );

        account.distributeMargin(newPositions);
    }

    // assert successful execution frees committed margin
    function testExecutionUncommitsMargin() public {
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        deposit(originalDeposit);

        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);
        mockGelato(0);

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);

        assertEq(account.committedMargin(), 0);
    }

    function testExecutionEmitsEvent() public {
        //setup
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        uint256 fee = 1;
        deposit(originalDeposit);

        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);
        mockGelato(fee);

        // provide account with fee balance
        cheats.deal(address(account), fee);

        cheats.expectEmit(true, false, false, true, address(account));
        emit OrderFilled(address(account), orderId, limitPrice, fee);

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);
    }

    function testExecutionEmitsFeeImposedEvent() public {
        //setup
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 ethPrice = 3e18;

        uint256 priceInUSD = (uint256(orderSizeDelta) * ethPrice) / 1e18;
        uint256 expectedFinalFeeCost = (priceInUSD *
            (TRADE_FEE + LIMIT_ORDER_FEE)) / 10_000;

        deposit(originalDeposit);

        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            ethPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, ethPrice);
        mockGelato(0);

        cheats.expectEmit(true, false, false, true, address(account));
        emit FeeImposed(address(account), expectedFinalFeeCost);

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);
    }

    // assert successful execution frees committed margin
    function testExecutionPaysGelato() public {
        uint256 existingGelatoBalance = address(gelato).balance;

        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        uint256 fee = 1;
        deposit(originalDeposit);

        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);

        mockGelato(fee);

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);

        assertEq(address(gelato).balance, existingGelatoBalance + fee);
    }

    // assert fee transfer to gelato is called
    function testFeeTransfer() public {
        assertEq(account.committedMargin(), 0);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        uint256 fee = 1;
        deposit(originalDeposit);

        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);

        mockGelato(fee);

        // expect a call w/ empty calldata to gelato (payment through callvalue)
        cheats.expectCall(gelato, "");

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);
    }

    // should 0 out committed margin
    function testCancellingLimitOrder() public {
        //setup
        assertEq(account.committedMargin(), 0);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        assertEq(account.committedMargin(), amount);

        // Mock non-returning function call
        (, , , , bytes32 taskId, , ) = account.orders(orderId);
        mockCall(
            account.ops(),
            abi.encodeWithSelector(IOps.cancelTask.selector, taskId)
        );

        account.cancelOrder(orderId);
        assertEq(account.committedMargin(), 0);
    }

    function testCancelOrderEmitsEvent() public {
        //setup
        assertEq(account.committedMargin(), 0);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        uint256 orderId = placeAdvancedOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice,
            IMarginBaseTypes.OrderTypes.LIMIT
        );
        assertEq(account.committedMargin(), amount);

        cheats.expectEmit(true, false, false, true, address(account));
        emit OrderCancelled(address(account), orderId);

        // Mock non-returning function call
        (, , , , bytes32 taskId, , ) = account.orders(orderId);
        mockCall(
            account.ops(),
            abi.encodeWithSelector(IOps.cancelTask.selector, taskId)
        );

        account.cancelOrder(orderId);
    }
}
