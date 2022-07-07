// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/interfaces/IFuturesMarket.sol";
import "../../contracts/interfaces/IFuturesMarketManager.sol";
import "../../contracts/interfaces/IAddressResolver.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "./utils/MintableERC20.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 private marginAsset;
    MarginAccountFactory private marginAccountFactory;
    MarginBase private account;

    // market keys
    bytes32 private ethMarketKey = "sETH";
    bytes32 private btcMarketKey = "sBTC";
    bytes32 private linkMarketKey = "sLINK";
    bytes32 private uniMarketKey = "sUNI";

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

    IOps private constant gelatoOps =
        IOps(0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c);
    address private constant gelato =
        0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;

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
            ethMarketKey,
            btcMarketKey,
            linkMarketKey,
            uniMarketKey
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

    function mockExternalCallsForPrice(address market, uint256 mockedPrice)
        internal
    {
        address exchangeRates = address(2);
        cheats.mockCall(
            market,
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

    function setUp() public {
        mockAddressResolverCalls();

        marginAsset = new MintableERC20(address(this), 0);
        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(marginAsset),
            address(addressResolver),
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
        address market,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 limitPrice
    ) internal {
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTask.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(0x1));
        account.placeOrder(market, marginDelta, sizeDelta, limitPrice);
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
        assertEq(marginAsset.balanceOf(address(account)), amount);
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
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    function testLimitValid() public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(account.validOrder(market));
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitValid(uint256 currentPrice) public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs greater than limit price
        cheats.assume(currentPrice <= expectedLimitPrice);

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(account.validOrder(market));
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitInvalid(uint256 currentPrice) public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs less than limit price
        cheats.assume(currentPrice > expectedLimitPrice);

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(!account.validOrder(market));
    }

    function testPlaceOrder() public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        (, , uint256 actualLimitPrice, ) = account.orders(market);
        assertEq(expectedLimitPrice, actualLimitPrice);
    }

    function testCommittingMargin() public {
        assertEq(account.committedMargin(), 0);
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        assertEq(account.committedMargin(), amount);
    }

    // assert cannot withdraw committed margin
    function testWithdrawingCommittedMargin() public {
        assertEq(account.committedMargin(), 0);
        address market = address(1);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);
        placeLimitOrder(
            market,
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
        address market = address(1);
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);

        // the maximum margin delta is positive 2^128 because it is int256
        cheats.assume(amountToCommit < 2**128 - 1);
        // this is a valid case (unless we want to restrict limit orders from not changing margin)
        cheats.assume(amountToCommit != 0);

        placeLimitOrder(
            market,
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
        address market = address(1);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 firstOrderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(originalDeposit);

        placeLimitOrder(
            market,
            int256(amountToCommit),
            firstOrderSizeDelta,
            expectedLimitPrice
        );

        int256 secondOrderMarginDelta = 1e18;
        int256 secondOrderSizeDelta = 1e18;
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](4);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            "sETH",
            secondOrderMarginDelta,
            secondOrderSizeDelta,
            false
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
        address market = address(1);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        uint256 fee = 1;
        deposit(originalDeposit);

        placeLimitOrder(
            market,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice
        );

        // make limit order condition
        mockExternalCallsForPrice(market, limitPrice);

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
        account.executeOrder(market);

        assertEq(account.committedMargin(), 0);
    }

    // assert fee transfer to gelato is called
    function testFeeTransfer() public {
        assertEq(account.committedMargin(), 0);
        address market = address(1);
        uint256 originalDeposit = 10e18;
        uint256 amountToCommit = originalDeposit;
        int256 orderSizeDelta = 1e18;
        uint256 limitPrice = 3e18;
        uint256 fee = 1;
        deposit(originalDeposit);

        placeLimitOrder(
            market,
            int256(amountToCommit),
            orderSizeDelta,
            limitPrice
        );

        // make limit order condition
        mockExternalCallsForPrice(market, limitPrice);

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
        account.executeOrder(market);
    }

    // should 0 out committed margin
    function testCancellingLimitOrder() public {
        assertEq(account.committedMargin(), 0);
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        assertEq(account.committedMargin(), amount);

        // Mock non-returning function call
        (, , , bytes32 taskId) = account.orders(market);
        mockCall(
            account.ops(),
            abi.encodeWithSelector(IOps.cancelTask.selector, taskId)
        );

        account.cancelOrder(market);
        assertEq(account.committedMargin(), 0);
    }

    /**********************************
     * testDistributeMargin()
     **********************************/
    function testDistributeMargin() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](4);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            linkMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[3] = MarginBase.UpdateMarketPositionSpec(
            uniMarketKey,
            1 ether,
            1 ether,
            false
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 4);
    }

    /// @dev DistributeMargin fuzz test
    function testDistributeMargin(uint16 numberOfNewPositions) public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](
                numberOfNewPositions
            );

        for (uint16 i = 0; i < numberOfNewPositions; i++) {
            newPositions[i] = MarginBase.UpdateMarketPositionSpec(
                ethMarketKey,
                1 ether,
                1 ether,
                false
            );
        }

        account.distributeMargin(newPositions);
        assertEq(
            account.getNumberOfActivePositions(),
            (numberOfNewPositions == 0 ? 0 : 1)
        );
    }

    function testCannotPassMaxPositions() public {
        uint32 max = type(uint16).max;
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](
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
        bytes32 key = "LUNA";
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](1);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            key,
            1 ether,
            1 ether,
            false
        );
        cheats.expectRevert();
        account.distributeMargin(newPositions);
    }

    /**********************************
     * getNumberOfActivePositions()
     **********************************/
    function testGetNumberOfActivePositionsReturnsZero() public {
        assertEq(account.getNumberOfActivePositions(), 0);
    }

    function testGetNumberOfActivePositions() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](2);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1 ether,
            1 ether,
            false
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
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](2);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1 ether,
            1 ether,
            false
        );
        account.distributeMargin(newPositions);
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            ethMarketKey
        );
        assertEq(
            account.getAllActiveMarketPositions()[1].marketKey,
            btcMarketKey
        );
    }

    function testCanGetActivePositionsAfterClosingOne() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](4);

        // close position which doesn't exist
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            uniMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[3] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );

        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 2);
        // @notice last added market should replace deleted market in array of market keys
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            uniMarketKey
        );
        assertEq(
            account.getAllActiveMarketPositions()[1].marketKey,
            btcMarketKey
        );
    }

    function testCanGetActivePositionsAfterClosingTwo() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](5);

        // close position which doesn't exist
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            uniMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );
        newPositions[3] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[4] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );

        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 1);
        assertEq(
            account.getAllActiveMarketPositions()[0].marketKey,
            uniMarketKey
        );
    }

    /**********************************
     * updateActiveMarketPosition()
     **********************************/
    function testCanUpdatePosition() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](2);

        // open position
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        // update position (same tx)
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            -1 ether, // reduce margin
            -1 ether, // reduce size
            false
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 1);
    }

    function testCanOpenRecentlyClosedPosition() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](3);

        // open position
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        // update position (same tx)
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true
        );
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 1);
    }

    /**********************************
     * closePositionAndWithdraw()
     * removeActiveMarketPositon()
     **********************************/
    function testCanRemovePosition() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](2);

        // close position which doesn't exist
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );

        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 0);
    }

    function testCannotRemoveNonexistentPosition() public {
        bytes32 aaveMarketKey = "sAAVE";
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](1);

        // close position which doesn't exist
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            aaveMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.MissingMarketKey.selector,
                aaveMarketKey
            )
        );
        account.distributeMargin(newPositions);
    }

    function testCannotClosePositionTwice() public {
        mockMarginBalance(1 ether);

        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](3);

        // open position
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1 ether,
            1 ether,
            false
        );
        // close position (same tx)
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );
        // attempt to close position *again* (same tx)
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            0,
            0,
            true // signals -> closePositionAndWithdraw()
        );
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginBase.MissingMarketKey.selector,
                ethMarketKey
            )
        );
        account.distributeMargin(newPositions);
    }
}
