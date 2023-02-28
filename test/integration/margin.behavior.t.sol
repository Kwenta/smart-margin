// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "../utils/AccountExposed.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {
    IAccount,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated
} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {IPerpsV2MarketSettings} from "@synthetix/IPerpsV2MarketSettings.sol";
import {ISynth} from "@synthetix/ISynth.sol";
import {OpsReady, IOps} from "../../src/utils/OpsReady.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract MarginBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Events private events;
    Factory private factory;
    ERC20 private sUSD;
    AccountExposed private accountExposed;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        sUSD = ERC20((IAddressResolver(ADDRESS_RESOLVER)).getAddress("ProxyERC20sUSD"));
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: TRADE_FEE,
            limitOrderFee: LIMIT_ORDER_FEE,
            stopOrderFee: STOP_ORDER_FEE
        });
        settings = Settings(factory.settings());
        events = Events(factory.events());
        accountExposed = new AccountExposed();
        accountExposed.setSettings(settings);
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            ACCOUNT CREATION
    //////////////////////////////////////////////////////////////*/

    function test_AccountCreated() external {
        Account account = createAccount();
        assert(address(account) != address(0));
        assert(address(account.settings()) == address(settings));
        assert(address(account.owner()) == address(this));
        assert(
            address(account.futuresMarketManager())
                == IAddressResolver(ADDRESS_RESOLVER).getAddress("FuturesMarketManager")
        );
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    /// @dev add tests for error FailedMarginTransfer()

    function test_CanMintSUSD() external {
        assert(sUSD.balanceOf(address(this)) == 0);
        mintSUSD(address(this), AMOUNT);
        assert(sUSD.balanceOf(address(this)) == AMOUNT);
    }

    function test_Deposit_Margin(uint256 x) external {
        Account account = createAccount();
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        assert(sUSD.balanceOf(address(account)) == 0);
        if (x == 0) {
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.deposit(x);
        } else if (x > AMOUNT) {
            vm.expectRevert();
            account.deposit(x);
        } else {
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(this), address(account), x);
            account.deposit(x);
            assert(sUSD.balanceOf(address(account)) == x);
        }
    }

    function test_Withdraw_Margin(uint256 x) external {
        Account account = createAccount();
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        account.deposit(AMOUNT);
        if (x == 0) {
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.withdraw(x);
        } else if (x > AMOUNT) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccount.InsufficientFreeMargin.selector, AMOUNT, x)
            );
            account.withdraw(x);
        } else {
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(this), address(account), x);
            account.withdraw(x);
            assert(sUSD.balanceOf(address(this)) == x);
            assert(sUSD.balanceOf(address(account)) == AMOUNT - x);
        }
    }

    function test_Deposit_ETH() external {
        Account account = createAccount();
        assert(address(account).balance == 0);
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
        assert(address(account).balance == 1 ether);
    }

    function test_Withdraw_Eth(uint256 x) external {
        Account account = createAccount();
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
        uint256 balance = address(account).balance;
        assert(balance == 1 ether);
        if (x > 1 ether) {
            vm.expectRevert(IAccount.EthWithdrawalFailed.selector);
            account.withdrawEth(x);
        } else if (x == 0) {
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.withdrawEth(x);
        } else {
            vm.expectEmit(true, true, true, true);
            emit EthWithdraw(address(this), address(account), x);
            account.withdrawEth(x);
            assert(address(account).balance == balance - x);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_Execute_InputCommandDifferingLengths() external {
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(0), 0);
        inputs[1] = abi.encode(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IAccount.LengthMismatch.selector));
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    function test_Dispatch_InvalidCommand() external {
        Account account = createAccountAndDepositSUSD(AMOUNT);
        bytes memory dataWithInvalidCommand = abi.encodeWithSignature(
            "execute(uint256,bytes)",
            69, // enums are rep as uint256 and there are not enough commands to reach 69
            abi.encode(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(IAccount.InvalidCommandType.selector, 69));
        (bool s,) = address(account).call(dataWithInvalidCommand);
        assert(!s);
    }

    // @AUDITOR increased scrutiny requested for invalid inputs
    function test_Dispatch_ValidCommand_InvalidInput() external {
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);

        // correct:
        // inputs[0] = abi.encode(market, marginDelta);

        // seemingly incorrect but actually works @AUDITOR:
        // inputs[0] = abi.encode(market, marginDelta, 69, address(0));

        // incorrect:
        inputs[0] = abi.encode(69);
        vm.expectRevert();
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                COMMANDS
    //////////////////////////////////////////////////////////////*/

    /*
        PERPS_V2_MODIFY_MARGIN
    */

    /// @notice test depositing margin into PerpsV2 market
    /// @dev test command: PERPS_V2_MODIFY_MARGIN
    function test_Commands_DepositMarginIntoMarket(int256 fuzzedMarginDelta) external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        uint256 accountBalance = sUSD.balanceOf(address(account));
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, fuzzedMarginDelta);

        /// @dev define & test outcomes:

        // outcome 1: margin delta cannot be zero
        if (fuzzedMarginDelta == 0) {
            vm.expectRevert(abi.encodeWithSelector(IAccount.InvalidMarginDelta.selector));
            account.execute(commands, inputs);
        }
        // outcome 2: margin delta is positive; thus a deposit
        if (fuzzedMarginDelta > 0) {
            if (fuzzedMarginDelta > int256(accountBalance)) {
                // outcome 2.1: margin delta larger than what is available in account
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IAccount.InsufficientFreeMargin.selector, accountBalance, fuzzedMarginDelta
                    )
                );
                account.execute(commands, inputs);
            } else {
                // outcome 2.2: margin delta deposited into market
                account.execute(commands, inputs);
                IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
                assert(int256(uint256(position.margin)) == fuzzedMarginDelta);
            }
        }
        // outcome 3: margin delta is negative; thus a withdrawal
        if (fuzzedMarginDelta < 0) {
            // outcome 3.1: there is no margin in market to withdraw
            vm.expectRevert();
            account.execute(commands, inputs);
        }
    }

    /// @notice test withdrawing margin from PerpsV2 market
    /// @dev test command: PERPS_V2_MODIFY_MARGIN
    function test_Commands_WithdrawMarginFromMarket(int256 fuzzedMarginDelta) external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        int256 balance = int256(sUSD.balanceOf(address(account)));
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, balance);
        account.execute(commands, inputs);
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, fuzzedMarginDelta);

        /// @dev define & test outcomes:

        // outcome 1: margin delta cannot be zero
        if (fuzzedMarginDelta == 0) {
            vm.expectRevert(abi.encodeWithSelector(IAccount.InvalidMarginDelta.selector));
            account.execute(commands, inputs);
        }
        // outcome 2: margin delta is positive; thus a deposit
        if (fuzzedMarginDelta > 0) {
            // outcome 2.1: there is no margin in account to deposit
            vm.expectRevert();
            account.execute(commands, inputs);
        }
        // outcome 3: margin delta is negative; thus a withdrawal
        if (fuzzedMarginDelta < 0) {
            if (fuzzedMarginDelta < balance * -1) {
                // outcome 3.1: margin delta larger than what is available in market
                vm.expectRevert();
                account.execute(commands, inputs);
            } else {
                // outcome 3.2: margin delta withdrawn from market
                account.execute(commands, inputs);
                IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
                assert(int256(uint256(position.margin)) == balance + fuzzedMarginDelta);
                assert(
                    sUSD.balanceOf(address(account)) == accountExposed.expose_abs(fuzzedMarginDelta)
                );
            }
        }
    }

    /*
        PERPS_V2_WITHDRAW_ALL_MARGIN
    */

    /// @notice test attempting to withdraw all account margin from PerpsV2 market that has none
    /// @dev test command: PERPS_V2_WITHDRAW_ALL_MARGIN
    function test_Commands_WithdrawAllMarginFromMarket_NoMargin() external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        uint256 preBalance = sUSD.balanceOf(address(account));
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);
        uint256 postBalance = sUSD.balanceOf(address(account));
        assertEq(preBalance, postBalance);
    }

    /// @notice test submitting and then withdrawing all account margin from PerpsV2 market
    /// @dev test command: PERPS_V2_WITHDRAW_ALL_MARGIN
    function test_Commands_WithdrawAllMarginFromMarket() external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        uint256 preBalance = sUSD.balanceOf(address(account));
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, int256(AMOUNT));
        account.execute(commands, inputs);
        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);
        uint256 postBalance = sUSD.balanceOf(address(account));
        assertEq(preBalance, postBalance);
    }

    /*
        PERPS_V2_SUBMIT_ATOMIC_ORDER
    */

    /// @notice test submitting atomic order
    /// @dev test command: PERPS_V2_SUBMIT_ATOMIC_ORDER
    function test_Commands_SubmitAtomicOrder() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
        assert(position.id != 0);
        assert(position.lastFundingIndex != 0);
        assert(position.margin != 0);
        assert(position.lastPrice != 0);
        assert(position.size != 0);
    }

    /*
        PERPS_V2_SUBMIT_DELAYED_ORDER
    */

    /// @notice test submitting delayed order
    /// @dev test command: PERPS_V2_SUBMIT_DELAYED_ORDER
    function test_Commands_SubmitDelayedOrder() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta, desiredTimeDelta);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == sizeDelta);
        assert(order.priceImpactDelta == priceImpactDelta);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit != 0);
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
    */

    /// @notice test submitting offchain delayed order
    /// @dev test command: PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
    function test_Commands_SubmitOffchainDelayedOrder() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == true);
        assert(order.sizeDelta == sizeDelta);
        assert(order.priceImpactDelta == priceImpactDelta);
        assert(order.targetRoundId != 0);
        assert(order.commitDeposit != 0);
        assert(order.keeperDeposit != 0);
        assert(order.executableAtTime != 0);
        assert(order.intentionTime != 0);
        assert(order.trackingCode == TRACKING_CODE);
    }

    /*
        PERPS_V2_CANCEL_DELAYED_ORDER
    */

    /// @notice test attempting to cancel a delayed order when none exists
    /// @dev test command: PERPS_V2_CANCEL_DELAYED_ORDER
    function test_Commands_CancelDelayedOrder_NoneExists() external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    /// @notice test submitting a delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_DELAYED_ORDER
    function test_Commands_CancelDelayedOrder() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta, desiredTimeDelta);
        account.execute(commands, inputs);
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.priceImpactDelta == 0);
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

    /// @notice test attempting to cancel an off-chain delayed order when none exists
    /// @dev test command: PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    function test_Commands_CancelOffchainDelayedOrder_NoneExists() external {
        address market = getMarketAddressFromKey(sETHPERP);
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    /// @notice test submitting an off-chain delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    function test_Commands_CancelOffchainDelayedOrder() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        // fast forward time
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 600 seconds);
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);
        assert(order.isOffchain == false);
        assert(order.sizeDelta == 0);
        assert(order.priceImpactDelta == 0);
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

    /// @notice test attempting to close a position when none exists
    /// @dev test command: PERPS_V2_CLOSE_POSITION
    function test_Commands_ClosePositionWhen_Exists() external {
        address market = getMarketAddressFromKey(sETHPERP);
        uint256 priceImpactDelta = 1 ether / 2;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    /// @notice test opening and then closing a position
    /// @notice specifically test Synthetix PerpsV2 position details after closing
    /// @dev test command: PERPS_V2_CLOSE_POSITION
    function test_Commands_ClosePosition() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        account.execute(commands, inputs);
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);
        account.execute(commands, inputs);
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
        assert(position.size == 0);
        assert(position.margin != 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TRADING FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice test trading fee is imposed when size delta is non-zero
    function test_TradeFee_SizeDeltaNonZero() external {
        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(market), marginDelta);
        inputs[1] = abi.encode(address(market), sizeDelta, priceImpactDelta);
        uint256 percentToTake = settings.tradeFee();
        uint256 fee = (accountExposed.expose_abs(sizeDelta) * percentToTake) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;
        vm.expectEmit(true, true, true, true);
        emit FeeImposed(address(account), feeInSUSD);
        account.execute(commands, inputs);
    }

    /// @notice test CannotPayFee error is emitted when fee exceeds free margin
    function test_TradeFee_ExceedFreeMargin() external {
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT); // deposit all SUSD from margin account into market
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        Account account = createAccountAndDepositSUSD(AMOUNT);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);
        vm.expectRevert(abi.encodeWithSelector(IAccount.CannotPayFee.selector));
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function mintSUSD(address to, uint256 amount) private {
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD = ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    function createAccount() private returns (Account account) {
        account = Account(payable(factory.newAccount()));
    }

    function createAccountAndDepositSUSD(uint256 amount) private returns (Account) {
        Account account = createAccount();
        mintSUSD(address(this), amount);
        sUSD.approve(address(account), amount);
        account.deposit(amount);
        vm.deal(address(account), 1 ether);
        return account;
    }

    function getMarketAddressFromKey(bytes32 key) private view returns (address market) {
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress("FuturesMarketManager")
                ).marketForKey(key)
            )
        );
    }
}
