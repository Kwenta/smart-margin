// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/interfaces/IFuturesMarket.sol";
import "../../contracts/interfaces/IFuturesMarketManager.sol";
import "../../contracts/interfaces/IAddressResolver.sol";
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

    // market keys
    bytes32 private ethMarketKey = "sETH";
    bytes32 private btcMarketKey = "sBTC";
    bytes32 private linkMarketKey = "sLINK";
    bytes32 private uniMarketKey = "sUNI";

    /// @notice max BPS
    uint256 private constant MAX_BPS = 10000;

    uint256 private constant INITIAL_MARGIN_ASSET_SUPPLY = 1000000 ether;

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

    /*///////////////////////////////////////////////////////////////
                                Setup
    ///////////////////////////////////////////////////////////////*/

    function setUp() public {
        mockAddressResolverCalls();

        /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
        uint256 distributionFee = 5; // 5 BPS
        uint256 limitOrderFee = 5; // 5 BPS
        uint256 stopLossFee = 10; // 10 BPS
        marginBaseSettings = new MarginBaseSettings(
            KWENTA_TREASURY,
            distributionFee,
            limitOrderFee,
            stopLossFee
        );

        marginAsset = new MintableERC20(
            address(this),
            INITIAL_MARGIN_ASSET_SUPPLY
        );

        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(marginAsset),
            address(addressResolver),
            address(marginBaseSettings)
        );
        account = MarginBase(marginAccountFactory.newAccount());

        marginAsset.transfer(address(account), INITIAL_MARGIN_ASSET_SUPPLY);

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
                                Unit Tests
    ///////////////////////////////////////////////////////////////*/

    /**********************************
     * deposit()
     * withdraw()
     *
     * @notice INITIAL_MARGIN_ASSET_SUPPLY was transferred to account in setup()
     * so that following tests do not fail when sending fee to kwenta treasury
     **********************************/
    function testDeposit() public {
        uint256 amount = 10 ether;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        assertEq(
            marginAsset.balanceOf(address(account)),
            (amount + INITIAL_MARGIN_ASSET_SUPPLY)
        );
    }

    function testWithdrawal() public {
        uint256 amount = 10 ether;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(
            marginAsset.balanceOf(address(account)),
            INITIAL_MARGIN_ASSET_SUPPLY
        );
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint256 amount) public {
        cheats.assume(amount > 0);
        cheats.assume(amount <= 10000000 ether); // 10_000_000
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(
            marginAsset.balanceOf(address(account)),
            INITIAL_MARGIN_ASSET_SUPPLY
        );
    }

    /**********************************
     * distributeMargin()
     **********************************/
    function testDistributeMargin() public {
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

    /**********************************
     * distribution fees
     **********************************/

    function testFeeDistribution() public {
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

        uint256 totalMarginMoved = 4 * (1 ether);
        uint256 expectedFee = (totalMarginMoved *
            marginBaseSettings.distributionFee()) / MAX_BPS;

        assertEq(marginAsset.balanceOf(KWENTA_TREASURY), expectedFee);
    }
}
