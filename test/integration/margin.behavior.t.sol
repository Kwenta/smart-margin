// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "../unit/utils/AccountExposed.sol";
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
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // establish sUSD address
        sUSD = ERC20((IAddressResolver(ADDRESS_RESOLVER)).getAddress("ProxyERC20sUSD"));

        // uses deployment script for tests (2 birds 1 stone)
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

        // deploy contract that exposes Account's internal functions
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

    /// @notice create account via the Factory
    /// @dev also tests that state variables properly set in constructor
    function testAccountCreated() external {
        // call factory to create account
        Account account = createAccount();

        // check account address exists
        assert(address(account) != address(0));

        // check correct values set in constructor
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

    /// @notice use helper function defined in this test contract
    /// to mint sUSD
    function testCanMintSUSD() external {
        // check this address has no sUSD
        assert(sUSD.balanceOf(address(this)) == 0);

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // check this address has sUSD
        assert(sUSD.balanceOf(address(this)) == AMOUNT);
    }

    /// @notice deposit sUSD into account
    function testDepositSUSD(uint256 x) external {
        // call factory to create account
        Account account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // check account has no sUSD
        assert(sUSD.balanceOf(address(account)) == 0);

        if (x == 0) {
            // attempt to deposit zero sUSD into account
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.deposit(x);
        } else if (x > AMOUNT) {
            // attempt to deposit sUSD into account
            vm.expectRevert();
            account.deposit(x);
        } else {
            // check deposit event emitted
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(this), address(account), x);

            // deposit sUSD into account
            account.deposit(x);

            // check account has sUSD
            assert(sUSD.balanceOf(address(account)) == x);
        }
    }

    /// @notice withdraw sUSD from account
    function testWithdrawSUSD(uint256 x) external {
        // call factory to create account
        Account account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        if (x == 0) {
            // attempt to withdraw zero sUSD from account
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.withdraw(x);
        } else if (x > AMOUNT) {
            // attempt to withdraw sUSD
            vm.expectRevert(
                abi.encodeWithSelector(IAccount.InsufficientFreeMargin.selector, AMOUNT, x)
            );
            account.withdraw(x);
        } else {
            // check withdraw event emitted
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(this), address(account), x);

            // withdraw sUSD from account
            account.withdraw(x);

            // check this address has sUSD
            assert(sUSD.balanceOf(address(this)) == x);

            // check account sUSD balance has decreased
            assert(sUSD.balanceOf(address(account)) == AMOUNT - x);
        }
    }

    /// @notice deposit ETH into account
    function testDepositETH() external {
        // call factory to create account
        Account account = createAccount();

        // check account has no ETH
        assert(address(account).balance == 0);

        // deposit ETH into account
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);

        // check account has ETH
        assert(address(account).balance == 1 ether);
    }

    /// @notice test only owner can withdraw ETH from account
    function testOnlyOwnerCanWithdrawETH() external {
        // call factory to create account
        Account account = createAccount();

        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // attempt to withdraw ETH
        vm.expectRevert("UNAUTHORIZED");
        account.withdrawEth(1 ether);
    }

    function testWithdrawEth(uint256 x) external {
        // call factory to create account
        Account account = createAccount();

        // send ETH to account
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);

        // check account has ETH
        uint256 balance = address(account).balance;
        assert(balance == 1 ether);

        if (x > 1 ether) {
            // attempt to withdraw ETH
            vm.expectRevert(IAccount.EthWithdrawalFailed.selector);
            account.withdrawEth(x);
        } else if (x == 0) {
            // attempt to withdraw ETH
            bytes32 valueName = "_amount";
            vm.expectRevert(abi.encodeWithSelector(IAccount.ValueCannotBeZero.selector, valueName));
            account.withdrawEth(x);
        } else {
            // check EthWithdraw event emitted
            vm.expectEmit(true, true, true, true);
            emit EthWithdraw(address(this), address(account), x);

            // withdraw ETH
            account.withdrawEth(x);

            // check account lost x ETH
            assert(address(account).balance == balance - x);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    /// @notice test providing non-matching command and input lengths
    function testCannotProvideNonMatchingCommandAndInputLengths() external {
        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(0), 0);
        inputs[1] = abi.encode(address(0), 0);

        // call execute (attempt to execute 1 command with 2 inputs)
        vm.expectRevert(abi.encodeWithSelector(IAccount.LengthMismatch.selector));
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    /// @notice test invalid command
    function testCannotExecuteInvalidCommand() external {
        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define calldata
        bytes memory dataWithInvalidCommand = abi.encodeWithSignature(
            "execute(uint256,bytes)",
            69, // enums are rep as uint256 and there are not enough commands to reach 69
            abi.encode(address(0))
        );

        // call execute (attempt to execute invalid command)
        vm.expectRevert(abi.encodeWithSelector(IAccount.InvalidCommandType.selector, 69));
        (bool s,) = address(account).call(dataWithInvalidCommand);
        assert(!s);
    }

    // @AUDITOR increased scrutiny requested for invalid inputs.
    /// @notice test invalid input with valid command
    function testFailExecuteInvalidInputWithValidCommand() external {
        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;

        // define invalid inputs
        bytes[] memory inputs = new bytes[](1);

        // correct:
        // inputs[0] = abi.encode(market, marginDelta);

        // seemingly incorrect but actually works @AUDITOR:
        // inputs[0] = abi.encode(market, marginDelta, 69, address(0));

        // incorrect:
        inputs[0] = abi.encode(69);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);

        // confirm position margin are non-zero
        assert(position.margin != 0);
    }

    /*//////////////////////////////////////////////////////////////
                                COMMANDS
    //////////////////////////////////////////////////////////////*/

    /*
        PERPS_V2_MODIFY_MARGIN
    */

    /// @notice test depositing margin into PerpsV2 market
    /// @dev test command: PERPS_V2_MODIFY_MARGIN
    function testDepositMarginIntoMarket(int256 fuzzedMarginDelta) external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // get account margin balance
        uint256 accountBalance = sUSD.balanceOf(address(account));

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
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
    function testWithdrawMarginFromMarket(int256 fuzzedMarginDelta) external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // get account margin balance
        int256 balance = int256(sUSD.balanceOf(address(account)));

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, balance);

        // call execute
        /// @dev depositing full margin account `balance` into market
        account.execute(commands, inputs);

        // define new inputs
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
                assert(sUSD.balanceOf(address(account)) == abs(fuzzedMarginDelta));
            }
        }
    }

    /*
        PERPS_V2_WITHDRAW_ALL_MARGIN
    */

    /// @notice test attempting to withdraw all account margin from PerpsV2 market that has none
    /// @dev test command: PERPS_V2_WITHDRAW_ALL_MARGIN
    function testWithdrawAllMarginFromMarketWithNoMargin() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // get account margin balance
        uint256 preBalance = sUSD.balanceOf(address(account));

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

        // get account margin balance
        uint256 postBalance = sUSD.balanceOf(address(account));

        // check margin account has same margin balance as before
        assertEq(preBalance, postBalance);
    }

    /// @notice test submitting and then withdrawing all account margin from PerpsV2 market
    /// @dev test command: PERPS_V2_WITHDRAW_ALL_MARGIN
    function testWithdrawAllMarginFromMarket() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // get account margin balance
        uint256 preBalance = sUSD.balanceOf(address(account));

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, int256(AMOUNT));

        // call execute
        account.execute(commands, inputs);

        // define commands
        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;

        // define inputs
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

        // get account margin balance
        uint256 postBalance = sUSD.balanceOf(address(account));

        // check margin account has same margin balance as before
        assertEq(preBalance, postBalance);
    }

    /*
        PERPS_V2_SUBMIT_ATOMIC_ORDER
    */

    /// @notice test submitting atomic order
    /// @dev test command: PERPS_V2_SUBMIT_ATOMIC_ORDER
    function testSubmitAtomicOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);

        // confirm position details are non-zero
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
    function testSubmitDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta, desiredTimeDelta);

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);

        // confirm delayed order details are non-zero
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
    function testSubmitOffchainDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);

        // confirm delayed order details are non-zero
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
    function testCancelDelayedOrderWhenNoneExists() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute (attempt to cancel delayed order)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    /// @notice test submitting a delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_DELAYED_ORDER
    function testCancelDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta, desiredTimeDelta);

        // call execute
        account.execute(commands, inputs);

        // define commands
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;

        // define inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);

        // expect all details to be unset
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
    function testCancelOffchainDelayedOrderWhenNoneExists() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute (attempt to cancel off-chain delayed order)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    /// @notice test submitting an off-chain delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    function testCancelOffchainDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // fast forward time
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 600 seconds);

        // define commands
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account.getDelayedOrder(sETHPERP);

        // expect all details to be unset
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
    function testClosePositionWhenNoneExists() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // call execute (attempt to close position when none exists)
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    /// @notice test opening and then closing a position
    /// @notice specifically test Synthetix PerpsV2 position details after closing
    /// @dev test command: PERPS_V2_CLOSE_POSITION
    function testClosePosition() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // redefine commands
        commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;

        // redefine inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);

        // expect size to be zero and margin to be non-zero
        assert(position.size == 0);
        assert(position.margin != 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TRADING FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice test trading fee is imposed when size delta is non-zero
    function testTradeFeeImposedWhenSizeDeltaNonZero() external {
        // define market
        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));

        // market and order related params
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(market), marginDelta);
        inputs[1] = abi.encode(address(market), sizeDelta, priceImpactDelta);

        // calculate expected fee
        uint256 percentToTake = settings.tradeFee();
        uint256 fee = (abs(sizeDelta) * percentToTake) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;

        // expect FeeImposed event on calling execute
        vm.expectEmit(true, true, true, true);
        emit FeeImposed(address(account), feeInSUSD);

        // call execute
        account.execute(commands, inputs);
    }

    /// @notice test CannotPayFee error is emitted when fee exceeds free margin
    function testTradeFeeCannotExceedFreeMargin() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT); // deposit all SUSD from margin account into market
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        Account account = createAccountAndDepositSUSD(AMOUNT);

        // define commands
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // expect CannotPayFee error on calling execute
        vm.expectRevert(abi.encodeWithSelector(IAccount.CannotPayFee.selector));

        // call execute
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // @HELPER
    /// @notice mint sUSD and transfer to address specified
    /// @dev Issuer.sol is an auxiliary helper contract that performs
    /// the issuing and burning functionality.
    /// Synth.sol is the base ERC20 token contract comprising most of
    /// the behaviour of all synths.
    /// Issuer is considered an "internal contract" therefore,
    /// it is permitted to call Synth.issue() which is restricted by
    /// the onlyInternalContracts modifier. Synth.issue() updates the
    /// token state (i.e. balance and total existing tokens) which effectively
    /// can be used to "mint" an account the underlying synth.
    /// @param to: address to mint and transfer sUSD to
    /// @param amount: amount to mint and transfer
    function mintSUSD(address to, uint256 amount) private {
        // fetch addresses needed
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD = ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));

        // set caller as issuer
        vm.prank(issuer);

        // mint sUSD
        synthsUSD.issue(to, amount);
    }

    // @HELPER
    /// @notice create margin base account
    /// @return account
    function createAccount() private returns (Account account) {
        // call factory to create account
        account = Account(payable(factory.newAccount()));
    }

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return Account account
    function createAccountAndDepositSUSD(uint256 amount) private returns (Account) {
        // call factory to create account
        Account account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), amount);

        // approve account to spend amount
        sUSD.approve(address(account), amount);

        // deposit sUSD into account
        account.deposit(amount);

        // send account eth for gas/trading
        (bool sent, bytes memory data) = address(account).call{value: 1 ether}("");
        assert(sent);
        assert(data.length == 0);

        return account;
    }

    // @HELPER
    /// @notice get address of market
    /// @return market address
    function getMarketAddressFromKey(bytes32 key) private view returns (address market) {
        // market and order related params
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress("FuturesMarketManager")
                ).marketForKey(key)
            )
        );
    }

    // @HELPER
    /// @notice get data needed for pranking Gelato calls to executeConditionalOrder
    /// @return executionData needed to call executeConditionalOrder
    /// @return moduleData needed to call Gelato's exec
    function generateGelatoModuleData(uint256 conditionalOrderId)
        internal
        pure
        returns (bytes memory executionData, IOps.ModuleData memory moduleData)
    {
        IOps.Module[] memory modules = new IOps.Module[](1);
        modules[0] = IOps.Module.RESOLVER;
        bytes[] memory args = new bytes[](1);
        args[0] = abi.encodeWithSelector(IAccount.checker.selector, conditionalOrderId);
        moduleData = IOps.ModuleData({modules: modules, args: args});
        executionData =
            abi.encodeWithSelector(IAccount.executeConditionalOrder.selector, conditionalOrderId);
    }

    // @HELPER
    /// @notice takes int and returns absolute value uint
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
