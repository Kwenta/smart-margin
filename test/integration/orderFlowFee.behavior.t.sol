// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {Setup} from "script/Deploy.s.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {Settings} from "src/Settings.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {AccountExposed} from "test/utils/AccountExposed.sol";
import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";

import {
    ADDRESS_RESOLVER,
    BLOCK_NUMBER,
    FUTURES_MARKET_MANAGER,
    GELATO,
    OPS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    SYSTEM_STATUS,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER
} from "test/utils/Constants.sol";

contract OrderFlowFeeTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Account private account;
    Settings private settings;

    // helper contracts for testing
    IERC20 private sUSD;
    AccountExposed private accountExposed;

    // constants
    uint256 private constant INITIAL_ORDER_FLOW_FEE = 5; // 0.005%

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory, events, settings,) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        // deploy an Account contract
        account = Account(payable(factory.newAccount()));

        // define helper contracts
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        sUSD = IERC20(addressResolver.getAddress(PROXY_SUSD));
        address futuresMarketManager =
            addressResolver.getAddress(FUTURES_MARKET_MANAGER);
        address systemStatus = addressResolver.getAddress(SYSTEM_STATUS);
        address perpsV2ExchangeRate =
            addressResolver.getAddress(PERPS_V2_EXCHANGE_RATE);

        // deploy AccountExposed contract for exposing internal account functions
        IAccount.AccountConstructorParams memory params = IAccount
            .AccountConstructorParams(
            address(factory),
            address(events),
            address(sUSD),
            perpsV2ExchangeRate,
            futuresMarketManager,
            systemStatus,
            GELATO,
            OPS,
            address(settings),
            UNISWAP_UNIVERSAL_ROUTER,
            UNISWAP_PERMIT2
        );
        accountExposed = new AccountExposed(params);

        // call approve() on an ERC20 to grant an infinite allowance to the SM account contract
        sUSD.approve(address(account), type(uint256).max);

        // set the order flow fee to a non-zero value
        settings.setOrderFlowFee(INITIAL_ORDER_FLOW_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @custom:todo use atomic order flow to simplify testing
    function test_calculateOrderFlowFee(uint256 fee) public {
        vm.assume(fee < settings.MAX_ORDER_FLOW_FEE());
        settings.setOrderFlowFee(fee);

        /// @custom:todo test the following:
        /// 1. what happens if {orderFlowFee} is zero
        /// 2. what happens if {orderFlowFee} is non-zero but fee is zero
        /// 3. what happens if {orderFlowFee} is non-zero and fee is non-zero
        /// 4. can division by zero occur
        /// 5. is division completely safe
        ///
        /// use public Account.getExpectedOrderFlowFee() to calculate the expected fee
        ///
        /// use fuzzing
    }

    /// @custom:todo use atomic order flow to simplify testing
    function test_imposeOrderFlowFee_account_margin() public {
        /// @custom:todo test the following assuming the account
        /// has sufficient margin:
        /// 1. is the fee sent to the correct address
        /// 2. can this be gameable at all
    }

    /// @custom:todo use atomic order flow to simplify testing
    function test_imposeOrderFlowFee_market_margin() public {
        /// @custom:todo test the following assuming the account
        /// has insufficient margin but the market has sufficient margin:
        /// 1. is the fee sent to the correct address
        /// 2. can this be gameable at all
        /// 3. is only what is necessary taken from the market
    }

    /// @custom:todo use atomic order flow to simplify testing
    function test_imposeOrderFlowFee_market_margin_failed() public {
        /// @custom:todo test the following assuming the account
        /// has insufficient margin and the market has insufficient margin
        /// (i.e., withdrawing from the market fails due to outstanding position or
        /// order exceeding allowed leverage if margin is taken):
        /// 1. error is caught for each scenario where the market margin is insufficient
    }

    /// @custom:todo desired fill price behaviour? floor/ceiling price behaviour? reverts? etc
    /// @custom:todo what happens if withdrawing margin from market results in leverage exceeding allowed leverage? revert?
    /// @custom:todo think deeply about the edge cases

    /// @custom:todo use atomic order flow to simplify testing
    function test_imposeOrderFlowFee_event() public {
        /// @custom:todo test the following:
        /// 1. is the correct event emitted
        /// 2. is the correct fee emitted with it
    }
}
