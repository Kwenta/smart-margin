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
    Account private account;
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

        account = Account(payable(factory.newAccount()));

        accountExposed = new AccountExposed();
        accountExposed.setFuturesMarketManager(IFuturesMarketManager(FUTURES_MARKET_MANAGER));
        accountExposed.setSettings(settings);
        accountExposed.setEvents(events);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_ETH() external {
        assert(address(account).balance == 0);
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s && address(account).balance == 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_Execute_InputCommandDifferingLengths() external {
        fundAccount(AMOUNT);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](2);

        vm.expectRevert(abi.encodeWithSelector(IAccount.LengthMismatch.selector));
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    function test_Dispatch_InvalidCommand() external {
        fundAccount(AMOUNT);

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
        fundAccount(AMOUNT);

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

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    /*
        ACCOUNT_MODIFY_MARGIN
    */

    /// @dev add tests for error FailedMarginTransfer()

    function test_Deposit_Margin(int256 x) external {
        vm.assume(x >= 0);

        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);

        if (x == 0) {
            // no-op
            modifyAccountMargin({amount: x});
        } else if (x > int256(AMOUNT)) {
            vm.expectRevert();
            modifyAccountMargin({amount: x});
        } else {
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(this), address(account), uint256(x));
            modifyAccountMargin({amount: x});
            assert(sUSD.balanceOf(address(account)) == uint256(x));
        }
    }

    function test_Withdraw_Margin(int256 x) external {
        vm.assume(x <= 0);

        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        modifyAccountMargin({amount: int256(AMOUNT)});

        if (x == 0) {
            // no-op
            modifyAccountMargin({amount: x});
        } else if (accountExposed.expose_abs(x) > AMOUNT) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccount.InsufficientFreeMargin.selector, AMOUNT, accountExposed.expose_abs(x)
                )
            );
            modifyAccountMargin({amount: x});
        } else {
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(this), address(account), accountExposed.expose_abs(x));
            modifyAccountMargin({amount: x});
            assert(sUSD.balanceOf(address(this)) == accountExposed.expose_abs(x));
            assert(sUSD.balanceOf(address(account)) == AMOUNT - accountExposed.expose_abs(x));
        }
    }

    /*
        ACCOUNT_WITHDRAW_ETH
    */

    function test_Withdraw_Eth(uint256 x) external {
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

    function test_Commands_ModifyMarginInMarket_NoExistingMarginInMarket(int256 fuzzedMarginDelta)
        external
    {
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
                        IAccount.InsufficientFreeMargin.selector, AMOUNT, fuzzedMarginDelta
                    )
                );
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
            } else if (fuzzedMarginDelta >= int256(AMOUNT)) {
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
                IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
                assert(int256(uint256(position.margin)) == fuzzedMarginDelta);
            }
        } else if (fuzzedMarginDelta < 0) {
            // there is no margin in market to withdraw
            vm.expectRevert();
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        }
    }

    function test_Commands_ModifyMarginInMarket_ExistingMarginInMarket(int256 fuzzedMarginDelta)
        external
    {
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
                    IAccount.InsufficientFreeMargin.selector, 0, fuzzedMarginDelta
                )
            );
            modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
        } else if (fuzzedMarginDelta < 0) {
            if (accountExposed.expose_abs(fuzzedMarginDelta) > AMOUNT) {
                // margin delta larger than what is available in market
                vm.expectRevert();
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
            } else {
                modifyMarketMargin({market: market, amount: fuzzedMarginDelta});
                IPerpsV2MarketConsolidated.Position memory position = account.getPosition(sETHPERP);
                assert(int256(uint256(position.margin)) == int256(AMOUNT) + fuzzedMarginDelta);
                assert(
                    sUSD.balanceOf(address(account)) == accountExposed.expose_abs(fuzzedMarginDelta)
                );
            }
        }
    }

    /*
        PERPS_V2_WITHDRAW_ALL_MARGIN
    */

    function test_Commands_WithdrawAllMarginFromMarket_NoExistingMarginInMarket() external {
        fundAccount(AMOUNT);

        uint256 preBalance = sUSD.balanceOf(address(account));

        withdrawAllMarketMargin({market: getMarketAddressFromKey(sETHPERP)});

        uint256 postBalance = sUSD.balanceOf(address(account));

        assertEq(preBalance, postBalance);
    }

    function test_Commands_WithdrawAllMarginFromMarket_ExistingMarginInMarket() external {
        fundAccount(AMOUNT);

        uint256 preBalance = sUSD.balanceOf(address(account));

        // deposit AMOUNT margin into market
        modifyMarketMargin({market: getMarketAddressFromKey(sETHPERP), amount: int256(AMOUNT)});

        withdrawAllMarketMargin({market: getMarketAddressFromKey(sETHPERP)});

        uint256 postBalance = sUSD.balanceOf(address(account));

        assertEq(preBalance, postBalance);
    }

    /*
        PERPS_V2_SUBMIT_ATOMIC_ORDER
    */

    function test_Commands_SubmitAtomicOrder() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

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

    function test_Commands_SubmitDelayedOrder() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;

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

    function test_Commands_SubmitOffchainDelayedOrder() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;

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

    function test_Commands_CancelDelayedOrder_NoneExists() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_Commands_CancelDelayedOrder() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;
        uint256 desiredTimeDelta = 0;

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

    function test_Commands_CancelOffchainDelayedOrder_NoneExists() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_Commands_CancelOffchainDelayedOrder() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;

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

    function test_Commands_ClosePositionWhen_Exists() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        uint256 priceImpactDelta = 1 ether / 2;

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_Commands_ClosePosition() external {
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

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
        fundAccount(AMOUNT);

        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

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
        fundAccount(AMOUNT);

        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT);
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

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

    function fundAccount(uint256 amount) private {
        vm.deal(address(account), 1 ether);
        mintSUSD(address(this), amount);
        sUSD.approve(address(account), amount);
        modifyAccountMargin({amount: int256(amount)});
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
