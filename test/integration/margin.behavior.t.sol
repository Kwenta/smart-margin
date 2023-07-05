// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Setup} from "script/Deploy.s.sol";

import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IFuturesMarketManager} from
    "src/interfaces/synthetix/IFuturesMarketManager.sol";
import {IPermit2} from "src/interfaces/uniswap/IPermit2.sol";
import {IPerpsV2MarketConsolidated} from "src/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";

import {AccountExposed} from "test/utils/AccountExposed.sol";
import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";

import {
    ADDRESS_RESOLVER,
    AMOUNT,
    BLOCK_NUMBER,
    ETH,
    FUTURES_MARKET_MANAGER,
    GELATO,
    OPS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    sETHPERP,
    SYSTEM_STATUS,
    TRACKING_CODE,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER
} from "test/utils/Constants.sol";

contract MarginBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Account private account;

    // helper contracts for testing
    IERC20 private sUSD;
    AccountExposed private accountExposed;

    IPermit2 private PERMIT2;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory, events,,) = setup.deploySystem({
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

        PERMIT2 = IPermit2(UNISWAP_PERMIT2);

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
            address(0),
            UNISWAP_UNIVERSAL_ROUTER,
            UNISWAP_PERMIT2
        );
        accountExposed = new AccountExposed(params);

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        sUSD.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via PERMIT2_PERMIT in production
        PERMIT2.approve(
            address(sUSD), address(account), type(uint160).max, type(uint48).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_ETH() public {
        assert(address(account).balance == 0);
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s && address(account).balance == 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_Execute_InputCommandDifferingLengths() public {
        fundAccount(AMOUNT);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](2);

        vm.expectRevert(
            abi.encodeWithSelector(IAccount.LengthMismatch.selector)
        );
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                COMMANDS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    /*
        ACCOUNT_MODIFY_MARGIN
    */

    function test_Deposit_Margin(uint256 x) public {
        vm.assume(x <= type(uint160).max);

        mintSUSD(address(this), AMOUNT);

        if (x == 0) {
            // no-op
            modifyAccountMargin({amount: int256(x)});
        } else if (x > AMOUNT) {
            vm.expectRevert("TRANSFER_FROM_FAILED");
            modifyAccountMargin({amount: int256(x)});
        } else {
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(this), address(account), uint256(x));
            modifyAccountMargin({amount: int256(x)});
            assert(sUSD.balanceOf(address(account)) == uint256(x));
        }
    }

    function test_Withdraw_Margin(int256 x) public {
        vm.assume(x <= 0);

        mintSUSD(address(this), AMOUNT);
        modifyAccountMargin({amount: int256(AMOUNT)});

        if (x == 0) {
            // no-op
            modifyAccountMargin({amount: x});
        } else if (accountExposed.expose_abs(x) > AMOUNT) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector,
                    AMOUNT,
                    accountExposed.expose_abs(x)
                )
            );
            modifyAccountMargin({amount: x});
        } else {
            vm.expectEmit(true, true, true, true);
            emit Withdraw(
                address(this), address(account), accountExposed.expose_abs(x)
            );
            modifyAccountMargin({amount: x});
            assert(
                sUSD.balanceOf(address(this)) == accountExposed.expose_abs(x)
            );
            assert(
                sUSD.balanceOf(address(account))
                    == AMOUNT - accountExposed.expose_abs(x)
            );
        }
    }

    /*
        ACCOUNT_WITHDRAW_ETH
    */

    function test_Withdraw_Eth(uint256 x) public {
        vm.deal(address(account), 1 ether);

        if (x == 0) {
            // no-op
            withdrawEth({amount: x});
        } else if (x > 1 ether) {
            vm.expectRevert(IAccount.EthWithdrawalFailed.selector);
            withdrawEth({amount: x});
        } else {
            vm.expectEmit(true, true, true, true);
            emit EthWithdraw(address(this), address(account), x);
            withdrawEth({amount: x});
            assert(address(account).balance == 1 ether - x);
        }
    }

    /*
        PERPS_V2_MODIFY_MARGIN
    */

    function test_Commands_ModifyMarginInMarket_NoExistingMarginInMarket(
        int256 fuzzedMarginDelta
    ) public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        if (fuzzedMarginDelta == 0) {
            // no-op
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        } else if (fuzzedMarginDelta > 0) {
            if (fuzzedMarginDelta > int256(AMOUNT)) {
                // account does not have enough margin to deposit
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IAccount.InsufficientFreeMargin.selector,
                        AMOUNT,
                        fuzzedMarginDelta
                    )
                );
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
            } else if (fuzzedMarginDelta >= int256(AMOUNT)) {
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
                IPerpsV2MarketConsolidated.Position memory position =
                    account.getPosition(sETHPERP);
                assert(int256(uint256(position.margin)) == fuzzedMarginDelta);
            }
        } else if (fuzzedMarginDelta < 0) {
            // there is no margin in market to withdraw
            vm.expectRevert("Insufficient margin");
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        }
    }

    function test_Commands_ModifyMarginInMarket_ExistingMarginInMarket(
        int256 fuzzedMarginDelta
    ) public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        // deposit AMOUNT margin into market
        modifyMarketMargin({market: market, amount: int256(AMOUNT)});

        if (fuzzedMarginDelta == 0) {
            // no-op
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        } else if (fuzzedMarginDelta > 0) {
            // account does not have enough margin to deposit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector,
                    0,
                    fuzzedMarginDelta
                )
            );
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        } else if (fuzzedMarginDelta < 0) {
            if (accountExposed.expose_abs(fuzzedMarginDelta) > AMOUNT) {
                // margin delta larger than what is available in market
                vm.expectRevert("Insufficient margin");
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
            } else {
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
                IPerpsV2MarketConsolidated.Position memory position =
                    account.getPosition(sETHPERP);
                assert(
                    int256(uint256(position.margin))
                        == int256(AMOUNT) + fuzzedMarginDelta
                );
                assert(
                    sUSD.balanceOf(address(account))
                        == accountExposed.expose_abs(fuzzedMarginDelta)
                );
            }
        }
    }

    /*
        PERPS_V2_WITHDRAW_ALL_MARGIN
    */

    function test_Commands_WithdrawAllMarginFromMarket_NoExistingMarginInMarket(
    ) public {
        fundAccount(AMOUNT);

        uint256 preBalance = sUSD.balanceOf(address(account));

        withdrawAllMarketMargin({market: getMarketAddressFromKey(sETHPERP)});

        uint256 postBalance = sUSD.balanceOf(address(account));

        assertEq(preBalance, postBalance);
    }

    function test_Commands_WithdrawAllMarginFromMarket_ExistingMarginInMarket()
        public
    {
        fundAccount(AMOUNT);

        uint256 preBalance = sUSD.balanceOf(address(account));

        // deposit AMOUNT margin into market
        modifyMarketMargin({
            market: getMarketAddressFromKey(sETHPERP),
            amount: int256(AMOUNT)
        });

        withdrawAllMarketMargin({market: getMarketAddressFromKey(sETHPERP)});

        uint256 postBalance = sUSD.balanceOf(address(account));

        assertEq(preBalance, postBalance);
    }

    /*
        PERPS_V2_SUBMIT_ATOMIC_ORDER
    */

    function test_Commands_SubmitAtomicOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);
        assert(position.id != 0);
        assert(position.lastFundingIndex != 0);
        assert(position.margin != 0);
        assert(position.lastPrice != 0);
        assert(position.size != 0);
    }

    /*
        PERPS_V2_SUBMIT_DELAYED_ORDER
    */

    function test_Commands_SubmitDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 desiredTimeDelta = 0;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] =
            abi.encode(market, sizeDelta, desiredTimeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == sizeDelta);
        assert(order.desiredFillPrice == desiredFillPrice);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit == 0); // no commit deposit post Almach release
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
    */

    function test_Commands_SubmitOffchainDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == true);
        assert(order.sizeDelta == sizeDelta);
        assert(order.desiredFillPrice == desiredFillPrice);
        assert(order.targetRoundId == 0); // off chain doesn’t use internal oracle so it’ll always be zero
        assert(order.commitDeposit == 0); // no commit deposit post Almach release
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime == 0); // only used for delayed (on-chain)
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*
        PERPS_V2_CANCEL_DELAYED_ORDER
    */

    function test_Commands_CancelDelayedOrder_NoneExists() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_Commands_CancelDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();
        uint256 desiredTimeDelta = 0;

        // create delayed order data
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] =
            abi.encode(market, sizeDelta, desiredTimeDelta, desiredFillPrice);

        // submit delayed order
        account.execute(commands, inputs);

        // fast forward time; must ff to allow order cancellations
        // (i.e. ff past the window of settlement)
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 10_000 seconds);

        // create cancel delayed order data
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // submit cancel delayed order data
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.desiredFillPrice == 0);
        assert(order.targetRoundId == 0);
        assert(order.commitDeposit == 0);
        assert(order.keeperDeposit == 0);
        assert(order.executableAtTime == 0);
        assert(order.intentionTime == 0);
        assert(order.trackingCode == "");
    }

    /*
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    */

    function test_Commands_CancelOffchainDelayedOrder_NoneExists() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_Commands_CancelOffchainDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        // fast forward time
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 600 seconds);

        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.desiredFillPrice == 0);
        assert(order.targetRoundId == 0);
        assert(order.commitDeposit == 0);
        assert(order.keeperDeposit == 0);
        assert(order.executableAtTime == 0);
        assert(order.intentionTime == 0);
        assert(order.trackingCode == "");
    }

    /*
        PERPS_V2_CLOSE_POSITION
    */

    function test_Commands_ClosePositionWhen_NoneExists() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, desiredFillPrice);

        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_Commands_ClosePosition() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 2;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        // define atomic order to open position
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);

        // open position
        account.execute(commands, inputs);

        // define close position order
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        inputs = new bytes[](1);
        desiredFillPrice -= 1 ether;
        inputs[0] = abi.encode(market, desiredFillPrice);

        // close position
        account.execute(commands, inputs);

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);
        assert(position.size == 0);
        assert(position.margin != 0);
    }

    /*
        PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER
    */

    function test_Commands_SubmitCloseDelayedOrder_NoneExists() public {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_Commands_SubmitCloseDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 2;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        // define atomic order to open position
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);

        // open position
        account.execute(commands, inputs);

        // define close position order
        commands = new IAccount.Command[](1);
        inputs = new bytes[](1);
        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER;
        inputs[0] =
            abi.encode(getMarketAddressFromKey(sETHPERP), 0, desiredFillPrice);

        // submit close position
        account.execute(commands, inputs);

        // check submitted order
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == -sizeDelta);
    }

    /*
        PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER
    */

    function test_Commands_SubmitCloseOffchainDelayedOrder_NoneExists()
        public
    {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] =
            IAccount.Command.PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0);

        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_Commands_SubmitCloseOffchainDelayedOrder() public {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        // define atomic order to open position
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);

        // open position
        account.execute(commands, inputs);

        // define close position order
        commands = new IAccount.Command[](1);
        inputs = new bytes[](1);
        commands[0] =
            IAccount.Command.PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER;
        inputs[0] =
            abi.encode(getMarketAddressFromKey(sETHPERP), desiredFillPrice);

        // submit close position
        account.execute(commands, inputs);

        // check submitted order
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == true);
        assert(order.sizeDelta == -sizeDelta);
    }

    /*//////////////////////////////////////////////////////////////
                               SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /*
        deposit margin into account -> deposit margin into market -> place delayed off-chain order
    */

    function test_Scenario_1() public {
        // mint sUSD to be deposited into account during execution
        mintSUSD(address(this), AMOUNT);

        // delayed off-chain order details
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        // init commands and inputs
        IAccount.Command[] memory commands = new IAccount.Command[](3);
        bytes[] memory inputs = new bytes[](3);

        // define commands
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[2] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        inputs[0] = abi.encode(AMOUNT);
        inputs[1] = abi.encode(market, marginDelta);
        inputs[2] = abi.encode(market, sizeDelta, desiredFillPrice);

        // execute commands w/ inputs
        account.execute(commands, inputs);

        // check margin has been deposited into market
        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);
        assert(position.margin != 0);

        // check some margin remains in account
        assert(account.freeMargin() != 0);

        // check order has been submitted
        IPerpsV2MarketConsolidated.DelayedOrder memory order =
            account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == true);
        assert(order.sizeDelta == sizeDelta);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function mintSUSD(address to, uint256 amount) private {
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD =
            ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    function fundAccount(uint256 amount) private {
        vm.deal(address(account), 1 ether);
        mintSUSD(address(this), amount);
        modifyAccountMargin({amount: int256(amount)});
    }

    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress(
                        "FuturesMarketManager"
                    )
                ).marketForKey(key)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                           COMMAND SHORTCUTS
    //////////////////////////////////////////////////////////////*/

    function modifyAccountMargin(int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function withdrawEth(uint256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_WITHDRAW_ETH;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function modifyMarketMargin(address market, int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, amount);
        account.execute(commands, inputs);
    }

    function withdrawAllMarketMargin(address market) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);
    }
}
