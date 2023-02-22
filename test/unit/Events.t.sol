// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Events} from "../../src/Events.sol";
import {IEvents} from "../../src/interfaces/IEvents.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";

contract EventsTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60_242_268;

    IAccount.ConditionalOrderTypes private constant ORDER_TYPE =
        IAccount.ConditionalOrderTypes.LIMIT;
    IAccount.ConditionalOrderCancelledReason private constant REASON =
        IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER;
    bool private constant REDUCE_ONLY = true;
    uint256 private constant AMOUNT = 2;
    uint256 private constant CONDITIONAL_ORDER_ID = 3;
    bytes32 private constant MARKET_KEY = "4";
    int256 private constant MARGIN_DELTA = 5;
    int256 private constant SIZE_DELTA = 6;
    uint256 private constant TARGET_PRICE = 7;
    uint128 private constant PRICE_IMPACT_DELTA = 8;
    uint256 private constant FILL_PRICE = 9;
    uint256 private constant KEEPER_FEE = 10;
    address private constant USER = address(0x11);
    address private constant ACCOUNT = address(0x12);

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
    event ConditionalOrderCancelled(
        address indexed account,
        uint256 conditionalOrderId,
        IAccount.ConditionalOrderCancelledReason reason
    );
    event ConditionalOrderFilled(
        address indexed account, uint256 conditionalOrderId, uint256 fillPrice, uint256 keeperFee
    );
    event FeeImposed(address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Events private events;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        events = new Events();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testEmitDeposit() public {
        vm.expectEmit(true, true, true, true);
        emit Deposit(USER, ACCOUNT, AMOUNT);
        events.emitDeposit({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function testEmitWithdraw() public {
        vm.expectEmit(true, true, true, true);
        emit Withdraw(USER, ACCOUNT, AMOUNT);
        events.emitWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function testEmitEthWithdraw() public {
        vm.expectEmit(true, true, true, true);
        emit EthWithdraw(USER, ACCOUNT, AMOUNT);
        events.emitEthWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function testEmitConditionalOrderPlaced() public {
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            ACCOUNT,
            CONDITIONAL_ORDER_ID,
            MARKET_KEY,
            MARGIN_DELTA,
            SIZE_DELTA,
            TARGET_PRICE,
            ORDER_TYPE,
            PRICE_IMPACT_DELTA,
            REDUCE_ONLY
            );
        events.emitConditionalOrderPlaced({
            account: ACCOUNT,
            conditionalOrderId: CONDITIONAL_ORDER_ID,
            marketKey: MARKET_KEY,
            marginDelta: MARGIN_DELTA,
            sizeDelta: SIZE_DELTA,
            targetPrice: TARGET_PRICE,
            conditionalOrderType: ORDER_TYPE,
            priceImpactDelta: PRICE_IMPACT_DELTA,
            reduceOnly: REDUCE_ONLY
        });
    }

    function testEmitConditionalOrderCancelled() public {
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(ACCOUNT, CONDITIONAL_ORDER_ID, REASON);
        events.emitConditionalOrderCancelled({
            account: ACCOUNT,
            conditionalOrderId: CONDITIONAL_ORDER_ID,
            reason: REASON
        });
    }

    function testEmitConditionalOrderFilled() public {
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(ACCOUNT, CONDITIONAL_ORDER_ID, FILL_PRICE, KEEPER_FEE);
        events.emitConditionalOrderFilled({
            account: ACCOUNT,
            conditionalOrderId: CONDITIONAL_ORDER_ID,
            fillPrice: FILL_PRICE,
            keeperFee: KEEPER_FEE
        });
    }

    function testEmitFeeImposed() public {
        vm.expectEmit(true, true, true, true);
        emit FeeImposed(ACCOUNT, AMOUNT);
        events.emitFeeImposed({account: ACCOUNT, amount: AMOUNT});
    }
}
