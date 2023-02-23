// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import "../utils/Constants.sol";

contract EventsTest is Test, ConsolidatedEvents {
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
        address account = address(0x1);
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
        uint256 id = 0;
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            ACCOUNT,
            id,
            sETHPERP,
            MARGIN_DELTA,
            SIZE_DELTA,
            TARGET_PRICE,
            IAccount.ConditionalOrderTypes.LIMIT,
            PRICE_IMPACT_DELTA,
            true
            );
        events.emitConditionalOrderPlaced({
            account: ACCOUNT,
            conditionalOrderId: id,
            marketKey: sETHPERP,
            marginDelta: MARGIN_DELTA,
            sizeDelta: SIZE_DELTA,
            targetPrice: TARGET_PRICE,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            priceImpactDelta: PRICE_IMPACT_DELTA,
            reduceOnly: true
        });
    }

    function testEmitConditionalOrderCancelled() public {
        uint256 id = 0;
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            ACCOUNT,
            id,
            IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER
            );
        events.emitConditionalOrderCancelled({
            account: ACCOUNT,
            conditionalOrderId: id,
            reason: IAccount.ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER
        });
    }

    function testEmitConditionalOrderFilled() public {
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(ACCOUNT, 0, FILL_PRICE, GELATO_FEE);
        events.emitConditionalOrderFilled({
            account: ACCOUNT,
            conditionalOrderId: 0,
            fillPrice: FILL_PRICE,
            keeperFee: GELATO_FEE
        });
    }

    function testEmitFeeImposed() public {
        vm.expectEmit(true, true, true, true);
        emit FeeImposed(ACCOUNT, AMOUNT);
        events.emitFeeImposed({account: ACCOUNT, amount: AMOUNT});
    }
}
