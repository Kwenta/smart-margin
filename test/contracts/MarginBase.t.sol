// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "../../contracts/interfaces/IFuturesMarket.sol";
import "./utils/MintableERC20.sol";

contract MarginAccountFactoryTest is DSTest {
    bytes32 private constant TRACKING_CODE = "KWENTA";

    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 private marginAsset;
    MarginAccountFactory private marginAccountFactory;
    MarginBase private account;

    struct Position {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    // futures market(s) for mocking
    IFuturesMarket private futuresMarketETH =
        IFuturesMarket(0xf86048DFf23cF130107dfB4e6386f574231a5C65);
    IFuturesMarket private futuresMarketBTC =
        IFuturesMarket(0xEe8804d8Ad10b0C3aD1Bd57AC3737242aD24bB95);
    IFuturesMarket private futuresMarketLINK =
        IFuturesMarket(0x1228c7D8BBc5bC53DB181bD7B1fcE765aa83bF8A);
    IFuturesMarket private futuresMarketUNI =
        IFuturesMarket(0x5Af0072617F7f2AEB0e314e2faD1DE0231Ba97cD);

    address private addressResolver =
        0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C;

    /**
     * Mocking FuturesMarket.sol
     *
     * @notice loop through each market and mock respective functions
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockFuturesMarketCalls() internal {
        IFuturesMarket[] memory marketsToMock = new IFuturesMarket[](4);
        marketsToMock[0] = futuresMarketETH;
        marketsToMock[1] = futuresMarketBTC;
        marketsToMock[2] = futuresMarketLINK;
        marketsToMock[3] = futuresMarketUNI;
        for (uint16 i = 0; i < 4; i++) {
            // @mock market.transferMargin()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.transferMargin.selector,
                    1e18
                ),
                abi.encode()
            );

            // @mock market.modifyPositionWithTracking()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encodeWithSelector(
                    IFuturesMarket.modifyPositionWithTracking.selector,
                    1e18
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
                abi.encode(Position(0, 0, 1e18, 1e18, 1e18))
            );

            // @mock market.withdrawAllMargin()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encode(IFuturesMarket.withdrawAllMargin.selector),
                abi.encode()
            );

            // @mock market.closePosition()
            cheats.mockCall(
                address(marketsToMock[i]),
                abi.encode(IFuturesMarket.closePosition.selector),
                abi.encode()
            );
        }
    }

    /********************** TESTS **********************/

    function setUp() public {
        marginAsset = new MintableERC20(address(this), 0);
        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(marginAsset),
            addressResolver
        );
        account = MarginBase(marginAccountFactory.newAccount());

        mockFuturesMarketCalls();
    }

    function testOwnership() public {
        assertEq(account.owner(), address(this));
    }

    function testExpectedMargin() public {
        assertEq(address(account.marginAsset()), address(marginAsset));
    }

    function testDeposit() public {
        uint256 amount = 10e18;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        assertEq(marginAsset.balanceOf(address(account)), amount);
    }

    function testWithdrawal() public {
        uint256 amount = 10e18;
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint256 amount) public {
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    // @TODO: testDistributeMargin()

    function testDistributeMargin() public {
        bytes32 ethMarketKey = "sETH";
        bytes32 btcMarketKey = "sBTC";
        bytes32 linkMarketKey = "sLINK";
        bytes32 uniMarketKey = "sUNI";
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](4);
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            ethMarketKey,
            1e18,
            1e18,
            false
        );
        newPositions[1] = MarginBase.UpdateMarketPositionSpec(
            btcMarketKey,
            1e18,
            1e18,
            false
        );
        newPositions[2] = MarginBase.UpdateMarketPositionSpec(
            linkMarketKey,
            1e18,
            1e18,
            false
        );
        newPositions[3] = MarginBase.UpdateMarketPositionSpec(
            uniMarketKey,
            1e18,
            1e18,
            false
        );
        account.distributeMargin(newPositions);
        assertEq(account.getNumberOfActivePositions(), 4);
    }

    // @TODO: getNumberOfActivePositions()

    // @TODO: getAllActiveMarketPositions()

    // @TODO: depositAndModifyPositionForMarket()

    // @TODO: closePositionAndWithdraw()

    // @TODO: updateActiveMarketPosition()

    // @TODO: removeActiveMarketPositon()
}
