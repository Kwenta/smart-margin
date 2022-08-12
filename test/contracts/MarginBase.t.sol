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
        IAddressResolver(0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C);
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
     * Mocking ExchangeRates.sol
     *
     * @param mockedMarket market to mock
     * @param mockedPrice price to return when effectiveValue() called
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockExchangeRates(IFuturesMarket mockedMarket, uint256 mockedPrice)
        internal
    {
        address exchangeRates = address(2);
        cheats.mockCall(
            address(mockedMarket),
            abi.encodePacked(IFuturesMarket.baseAsset.selector),
            abi.encode("sSYNTH")
        );
        cheats.mockCall(
            address(addressResolver),
            abi.encodePacked(IAddressResolver.requireAndGetAddress.selector),
            abi.encode(exchangeRates)
        );
        cheats.mockCall(
            exchangeRates,
            abi.encodePacked(IExchangeRates.effectiveValue.selector),
            abi.encode(mockedPrice)
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

    function placeLimitOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 limitPrice
    ) internal returns (uint256 orderId) {
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        orderId = account.placeOrder(
            marketKey,
            marginDelta,
            sizeDelta,
            limitPrice
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

    /**********************************
     * deposit()
     * withdraw()
     **********************************/
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

    function testEthDepositWithdrawal() public payable {
        uint256 amount = 1 ether;
        cheats.deal(address(this), amount);

        // Deposit
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTaskNoPrepayment.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        account.placeOrder{value: amount}(ETH_MARKET_KEY, 0, 1, 0);

        // Withdraw
        account.withdrawEth(amount);
    }

    function testLimitValid() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;

        // Setup
        deposit(amount);
        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        assertTrue(account.validOrder(orderId));
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
        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        assertTrue(account.validOrder(orderId));
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
        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExchangeRates(futuresMarketETH, currentPrice);
        assertTrue(!account.validOrder(orderId));
    }

    function testPlaceOrder() public {
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        (, , , uint256 actualLimitPrice, ) = account.orders(orderId);
        assertEq(expectedLimitPrice, actualLimitPrice);
    }

    function testCommittingMargin() public {
        assertEq(account.committedMargin(), 0);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
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
        placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            expectedLimitPrice
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

        placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            expectedLimitPrice
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

        placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            firstOrderSizeDelta,
            expectedLimitPrice
        );

        int256 secondOrderMarginDelta = 1e18;
        int256 secondOrderSizeDelta = 1e18;
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                4
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
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
        uint256 fee = 1;
        deposit(originalDeposit);

        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);

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

        // provide account with fee balance
        cheats.deal(address(account), fee);

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);

        assertEq(account.committedMargin(), 0);
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

        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice
        );

        // make limit order condition
        mockExchangeRates(futuresMarketETH, limitPrice);

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

        // provide account with fee balance
        cheats.deal(address(account), fee);

        // expect a call w/ empty calldata to gelato (payment through callvalue)
        cheats.expectCall(gelato, "");

        // call as ops
        cheats.prank(address(gelatoOps));
        account.executeOrder(orderId);
    }

    // should 0 out committed margin
    function testCancellingLimitOrder() public {
        assertEq(account.committedMargin(), 0);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        uint256 orderId = placeLimitOrder(
            ETH_MARKET_KEY,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        assertEq(account.committedMargin(), amount);

        // Mock non-returning function call
        (, , , , bytes32 taskId) = account.orders(orderId);
        mockCall(
            account.ops(),
            abi.encodeWithSelector(IOps.cancelTask.selector, taskId)
        );

        account.cancelOrder(orderId);
        assertEq(account.committedMargin(), 0);
    }

    /**********************************
     * distributeMargin()
     **********************************/
    function testDistributeMargin() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                4
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[2] = IMarginBaseTypes.UpdateMarketPositionSpec(
            LINK_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[3] = IMarginBaseTypes.UpdateMarketPositionSpec(
            UNI_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 4);
    }

    /// @dev DistributeMargin fuzz test
    function testDistributeMargin(uint8 numberOfNewPositions) public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                numberOfNewPositions
            );

        for (uint16 i = 0; i < numberOfNewPositions; i++) {
            newPositions[i] = IMarginBaseTypes.UpdateMarketPositionSpec(
                ETH_MARKET_KEY,
                1 ether,
                1 ether
            );
        }

        account.distributeMargin(newPositions);
        assertEq(
            account.getNumberOfActivePositions(),
            (numberOfNewPositions == 0 ? 0 : 1)
        );
    }

    function testCannotPassMaxPositions() public {
        mockExchangeRatesForDistributionTests();

        uint32 max = type(uint16).max;
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                max + 1
            );

        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.MaxNewPositionsExceeded.selector,
                max + 1
            )
        );
        account.distributeMargin(newPositions);
    }

    function testCannotDistributeMarginWithInvalidKey() public {
        mockExchangeRatesForDistributionTests();

        bytes32 key = "LUNA";
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            key,
            1 ether,
            1 ether
        );
        cheats.expectRevert();
        account.distributeMargin(newPositions);
    }

    /**********************************
     * depositAndDistribute()
     **********************************/
    function testDepositAndDistribute() public {
        uint256 amount = 5 ether;
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                2
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );

        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);

        account.depositAndDistribute(amount, newPositions);
        assertEq(account.getNumberOfActivePositions(), 2);
    }

    function testCannotDepositAndDistributeAsNonOwner() public {
        uint256 amount = 5 ether;
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );

        marginAsset.mint(nonOwnerEOA, amount);
        marginAsset.approve(nonOwnerEOA, amount);

        cheats.expectRevert(
            abi.encodePacked("Ownable: caller is not the owner")
        );
        cheats.prank(nonOwnerEOA); // non-owner calling depositAndDistribute()
        account.depositAndDistribute(amount, newPositions);
    }

    /**********************************
     * getNumberOfActivePositions()
     **********************************/
    function testGetNumberOfActivePositionsReturnsZero() public {
        assertEq(account.getNumberOfActivePositions(), 0);
    }

    function testGetNumberOfActivePositions() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                2
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 2);
    }

    /**********************************
     * getAllActiveMarketPositions()
     * @notice position.margin and position.size are calculated by Synthetix
     *         so they're not tested here (and are in-fact mocked above)
     **********************************/
    function testCanGetActivePositions() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                2
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            ETH_MARKET_KEY
        );
        assertEq(
            account.getAllActiveMarketPositions()[1].marketKey,
            BTC_MARKET_KEY
        );
    }

    function testCanGetActivePositionsAfterClosingOne() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                3
            );

        // close position which doesn't exist
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[2] = IMarginBaseTypes.UpdateMarketPositionSpec(
            UNI_MARKET_KEY,
            1 ether,
            1 ether
        );

        account.distributeMargin(newPositions);

        // @mock market.positions()
        // update mocking so size returned from Synthetix Futures contracts is "0"
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // modify positions so size is 0
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions2 = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions2[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );

        account.distributeMargin(newPositions2);

        assertEq(account.getNumberOfActivePositions(), 2);
        // @notice last added market should replace deleted market in array of market keys
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            UNI_MARKET_KEY
        );
        assertEq(
            account.getAllActiveMarketPositions()[1].marketKey,
            BTC_MARKET_KEY
        );
    }

    function testCanGetActivePositionsAfterClosingTwo() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        // open 3 positions
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                3
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            UNI_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[2] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);

        // @mock market.positions()
        // update mocking so size returned from Synthetix Futures contracts is "0"
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );
        cheats.mockCall(
            address(futuresMarketBTC),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // modify positions so size is 0
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions2 = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                2
            );
        newPositions2[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );
        newPositions2[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            0,
            -1 ether
        );

        account.distributeMargin(newPositions2);

        assertEq(account.getNumberOfActivePositions(), 1);
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            UNI_MARKET_KEY
        );
    }

    /**********************************
     * updateActiveMarketPosition()
     **********************************/
    function testCanUpdatePosition() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                2
            );

        // open position
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        // update position (same tx)
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            -1 ether, // reduce margin
            -1 ether // reduce size
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 1);
    }

    function testCanOpenRecentlyClosedPosition() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                3
            );

        // open position
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        // update position (same tx)
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            0
        );
        newPositions[2] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 1);
    }

    /**********************************
     * closePositionAndWithdraw()
     * removeActiveMarketPositon()
     **********************************/
    function testCanRemovePosition() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );

        // close position which doesn't exist
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );

        account.distributeMargin(newPositions);

        // @mock market.positions()
        // update mocking so size returned from Synthetix Futures contracts is "0"
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // modify positions so size is 0
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions2 = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions2[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );

        account.distributeMargin(newPositions2);

        assertEq(account.getNumberOfActivePositions(), 0);
    }

    function testCannotRemoveNonexistentPosition() public {
        mockExchangeRatesForDistributionTests();

        // @mock market.positions()
        // update mocking so size returned from Synthetix Futures contracts is "0"
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // modify positions so size is 0
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );

        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.MissingMarketKey.selector,
                ETH_MARKET_KEY
            )
        );
        account.distributeMargin(newPositions);
    }

    function testCannotClosePositionTwice() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );

        // open position
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );

        account.distributeMargin(newPositions);

        // @mock market.positions()
        // update mocking so size returned from Synthetix Futures contracts is "0"
        cheats.mockCall(
            address(futuresMarketETH),
            abi.encodeWithSelector(
                IFuturesMarket.positions.selector,
                address(account)
            ),
            abi.encode(Position(0, 0, 1 ether, 1 ether, 0)) // size = 0
        );

        // modify positions so size is 0
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions2 = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );
        newPositions2[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );

        account.distributeMargin(newPositions2);

        // modify positions so size is 0 (again)
        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions3 = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                1
            );

        newPositions3[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            0,
            -1 ether
        );

        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.MissingMarketKey.selector,
                ETH_MARKET_KEY
            )
        );
        account.distributeMargin(newPositions3);
    }

    /**********************************
     * trade fees
     **********************************/

    function testTradeFee() public {
        deposit(1 ether);
        mockExchangeRatesForDistributionTests();

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                4
            );
        newPositions[0] = IMarginBaseTypes.UpdateMarketPositionSpec(
            ETH_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[1] = IMarginBaseTypes.UpdateMarketPositionSpec(
            BTC_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[2] = IMarginBaseTypes.UpdateMarketPositionSpec(
            LINK_MARKET_KEY,
            1 ether,
            1 ether
        );
        newPositions[3] = IMarginBaseTypes.UpdateMarketPositionSpec(
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

        IMarginBaseTypes.UpdateMarketPositionSpec[]
            memory newPositions = new IMarginBaseTypes.UpdateMarketPositionSpec[](
                255
            );

        for (uint8 i = 0; i < 255; i++) {
            newPositions[i] = IMarginBaseTypes.UpdateMarketPositionSpec(
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

    /**********************************
     * rescueERC20
     **********************************/

    function testCanRescueToken() public {
        MintableERC20 token = new MintableERC20(address(this), 1 ether);
        token.transfer(address(account), 1 ether);
        assertEq(token.balanceOf(address(this)), 0);
        account.rescueERC20(address(token), 1 ether);
        assertEq(token.balanceOf(address(this)), 1 ether);
    }

    function testCantRescueMarginAssetToken() public {
        marginAsset.mint(address(this), 1 ether);
        marginAsset.transfer(address(account), 1 ether);
        assertEq(marginAsset.balanceOf(address(this)), 0);
        cheats.expectRevert(
            abi.encodeWithSelector(MarginBase.CannotRescueMarginAsset.selector)
        );
        account.rescueERC20(address(marginAsset), 1 ether);
    }

    function testCantRescueTokenIfNotOwner() public {
        MintableERC20 token = new MintableERC20(address(this), 1 ether);
        token.transfer(address(account), 1 ether);
        cheats.expectRevert(
            abi.encodePacked("Ownable: caller is not the owner")
        );
        cheats.prank(nonOwnerEOA); // non-owner calling rescueERC20()
        account.rescueERC20(address(token), 1 ether);        
    }
}
