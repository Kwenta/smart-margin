// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Events} from "../../src/Events.sol";
import {IEvents} from "../../src/interfaces/IEvents.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";

contract EventsTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    Events private events;

    uint256 private constant AMOUNT = 1;
    uint256 private constant ORDER_ID = 2;
    bytes32 private constant MARKET_KEY = "ETH";
    int256 private constant MARGIN_DELTA = 4;
    int256 private constant SIZE_DELTA = 5;
    uint256 private constant TARGET_PRICE = 6;
    IAccount.OrderTypes private constant ORDER_TYPE = IAccount.OrderTypes.LIMIT;
    uint128 private constant PRICE_IMPACT_DELTA = 7;
    uint256 private constant MAX_DYNAMIC_FEE = 8;
    uint256 private constant FILL_PRICE = 9;
    uint256 private constant KEEPER_FEE = 10;

    event Deposit(address indexed account, uint256 amountDeposited);
    event Withdraw(address indexed account, uint256 amountWithdrawn);
    event EthWithdraw(address indexed account, uint256 amountWithdrawn);
    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.OrderTypes orderType,
        uint128 priceImpactDelta,
        uint256 maxDynamicFee
    );
    event OrderCancelled(address indexed account, uint256 orderId);
    event OrderFilled(
        address indexed account,
        uint256 orderId,
        uint256 fillPrice,
        uint256 keeperFee
    );
    event FeeImposed(address indexed account, uint256 amount);

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        events = new Events();
    }

    function testEmitDeposit() public {
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), AMOUNT);
        events.emitDeposit({account: address(this), amountDeposited: AMOUNT});
    }

    function testEmitWithdraw() public {
        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), AMOUNT);
        events.emitWithdraw({account: address(this), amountWithdrawn: AMOUNT});
    }

    function testEmitEthWithdraw() public {
        vm.expectEmit(true, true, true, true);
        emit EthWithdraw(address(this), AMOUNT);
        events.emitEthWithdraw({
            account: address(this),
            amountWithdrawn: AMOUNT
        });
    }

    function testEmitOrderPlaced() public {
        vm.expectEmit(true, true, true, true);
        emit OrderPlaced(
            address(this),
            ORDER_ID,
            MARKET_KEY,
            MARGIN_DELTA,
            SIZE_DELTA,
            TARGET_PRICE,
            ORDER_TYPE,
            PRICE_IMPACT_DELTA,
            MAX_DYNAMIC_FEE
        );
        events.emitOrderPlaced({
            account: address(this),
            orderId: ORDER_ID,
            marketKey: MARKET_KEY,
            marginDelta: MARGIN_DELTA,
            sizeDelta: SIZE_DELTA,
            targetPrice: TARGET_PRICE,
            orderType: ORDER_TYPE,
            priceImpactDelta: PRICE_IMPACT_DELTA,
            maxDynamicFee: MAX_DYNAMIC_FEE
        });
    }

    function testEmitOrderCancelled() public {
        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(address(this), ORDER_ID);
        events.emitOrderCancelled({account: address(this), orderId: ORDER_ID});
    }

    function testEmitOrderFilled() public {
        vm.expectEmit(true, true, true, true);
        emit OrderFilled(address(this), ORDER_ID, FILL_PRICE, KEEPER_FEE);
        events.emitOrderFilled({
            account: address(this),
            orderId: ORDER_ID,
            fillPrice: FILL_PRICE,
            keeperFee: KEEPER_FEE
        });
    }

    function testEmitFeeImposed() public {
        vm.expectEmit(true, true, true, true);
        emit FeeImposed(address(this), AMOUNT);
        events.emitFeeImposed({account: address(this), amount: AMOUNT});
    }
}
