// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account, Auth} from "../../src/Account.sol";
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
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

contract AccountTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Events private events;
    Factory private factory;
    Account private account;
    AccountExposed private accountExposed;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            isMainnet: false,
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: TRADE_FEE,
            limitOrderFee: LIMIT_ORDER_FEE,
            stopOrderFee: STOP_ORDER_FEE,
            addressResolver: ADDRESS_RESOLVER,
            marginAsset: MARGIN_ASSET,
            gelato: GELATO,
            ops: OPS
        });

        settings = Settings(factory.settings());
        events = Events(factory.events());

        account = Account(payable(factory.newAccount()));

        accountExposed = new AccountExposed();
        accountExposed.setFuturesMarketManager(
            IFuturesMarketManager(account.futuresMarketManager())
        );
        accountExposed.setSettings(settings);
        accountExposed.setEvents(events);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_GetVerison() external view {
        assert(account.VERSION() == "2.0.0");
    }

    function test_GetFactory() external view {
        assert(account.factory() == factory);
    }

    function test_GetFuturesMarketManager() external view {
        assert(address(account.futuresMarketManager()) != address(0));
    }

    function test_GetSettings() external view {
        assert(account.settings() == settings);
    }

    function test_GetEvents() external view {
        assert(account.events() == events);
    }

    function test_GetCommittedMargin() external view {
        assert(account.committedMargin() == 0);
    }

    function test_GetConditionalOrderId() external view {
        assert(account.conditionalOrderId() == 0);
    }

    function test_GetDelayedOrder_EthMarket() external {
        IPerpsV2MarketConsolidated.DelayedOrder memory delayedOrder =
            account.getDelayedOrder({_marketKey: sETHPERP});
        assertEq(delayedOrder.isOffchain, false);
        assertEq(delayedOrder.sizeDelta, 0);
        assertEq(delayedOrder.desiredFillPrice, 0);
        assertEq(delayedOrder.targetRoundId, 0);
        assertEq(delayedOrder.commitDeposit, 0);
        assertEq(delayedOrder.keeperDeposit, 0);
        assertEq(delayedOrder.executableAtTime, 0);
        assertEq(delayedOrder.intentionTime, 0);
        assertEq(delayedOrder.trackingCode, "");
    }

    function test_GetDelayedOrder_InvalidMarket() external {
        vm.expectRevert();
        account.getDelayedOrder({_marketKey: "unknown"});
    }

    function test_Checker() external {
        vm.expectRevert();
        account.checker({_conditionalOrderId: 0});
    }

    function test_GetFreeMargin() external {
        assertEq(account.freeMargin(), 0);
    }

    function test_GetPosition_EthMarket() external {
        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition({_marketKey: sETHPERP});
        assertEq(position.id, 0);
        assertEq(position.lastFundingIndex, 0);
        assertEq(position.margin, 0);
        assertEq(position.lastPrice, 0);
        assertEq(position.size, 0);
    }

    function test_GetPosition_InvalidMarket() external {
        vm.expectRevert();
        account.getPosition({_marketKey: "unknown"});
    }

    function test_GetConditionalOrder() external {
        IAccount.ConditionalOrder memory conditionalOrder =
            account.getConditionalOrder({_conditionalOrderId: 0});
        assertEq(conditionalOrder.marketKey, "");
        assertEq(conditionalOrder.marginDelta, 0);
        assertEq(conditionalOrder.sizeDelta, 0);
        assertEq(conditionalOrder.targetPrice, 0);
        assertEq(conditionalOrder.gelatoTaskId, "");
        assertEq(
            uint256(conditionalOrder.conditionalOrderType),
            uint256(IAccount.ConditionalOrderTypes.LIMIT)
        );
        assertEq(conditionalOrder.desiredFillPrice, 0);
        assertEq(conditionalOrder.reduceOnly, false);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_Ownership_Transfer() external {
        // ensure factory and account state align
        address currentOwner = factory.getAccountOwner(address(account));
        assert(
            currentOwner == address(this) && currentOwner == account.owner()
                && currentOwner != KWENTA_TREASURY
        );
        assert(factory.getAccountsOwnedBy(currentOwner)[0] == address(account));

        // transfer ownership
        account.transferOwnership(KWENTA_TREASURY);
        assert(account.owner() == KWENTA_TREASURY);

        // ensure factory and account state align
        currentOwner = factory.getAccountOwner(address(account));
        assert(
            currentOwner == KWENTA_TREASURY && currentOwner == account.owner()
        );
        assert(
            factory.getAccountsOwnedBy(KWENTA_TREASURY)[0] == address(account)
        );
    }

    function test_Ownership_Transfer_Event() external {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), KWENTA_TREASURY);
        account.transferOwnership(KWENTA_TREASURY);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Margin_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(int256(AMOUNT));
    }

    function test_Withdraw_Margin_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(-int256(AMOUNT));
    }

    function test_Deposit_ETH_AnyCaller() external {
        account.transferOwnership(KWENTA_TREASURY);
        (bool s,) = address(account).call{value: 1 ether}("");
        assert(s);
    }

    function test_Withdraw_ETH_OnlyOwner() external {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        withdrawEth(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             FEE UTILITIES
    //////////////////////////////////////////////////////////////*/

    function test_CalculateFee_EthMarket(int128 fuzzedSizeDelta) external {
        uint256 conditionalOrderFee = MAX_BPS / 99;
        IPerpsV2MarketConsolidated market =
            IPerpsV2MarketConsolidated(getMarketAddressFromKey(sETHPERP));
        uint256 percentToTake = settings.tradeFee() + conditionalOrderFee;
        uint256 fee = (
            accountExposed.expose_abs(int256(fuzzedSizeDelta)) * percentToTake
        ) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;
        uint256 actualFee = accountExposed.expose_calculateFee({
            _sizeDelta: fuzzedSizeDelta,
            _market: market,
            _conditionalOrderFee: conditionalOrderFee
        });
        assertEq(actualFee, feeInSUSD);
    }

    function test_CalculateFee_InvalidMarket() external {
        int256 sizeDelta = -1 ether;
        vm.expectRevert();
        accountExposed.expose_calculateFee({
            _sizeDelta: sizeDelta,
            _market: IPerpsV2MarketConsolidated(address(0)),
            _conditionalOrderFee: LIMIT_ORDER_FEE
        });
    }

    /*//////////////////////////////////////////////////////////////
                               DELEGATION
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      ADD/REMOVE DELEGATED TRADERS
    //////////////////////////////////////////////////////////////*/

    function test_AddDelegatedTrader() public {
        account.addDelegate({_delegate: DELEGATE});
        assert(account.delegates(DELEGATE));
    }

    function test_AddDelegatedTrader_Event() public {
        vm.expectEmit(true, true, true, true);
        emit DelegatedAccountAdded(address(this), DELEGATE);
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_AddDelegatedTrader_OnlyOwner() public {
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_AddDelegatedTrader_ZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, address(0)
            )
        );
        account.addDelegate({_delegate: address(0)});
    }

    function test_AddDelegatedTrader_AlreadyDelegated() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, DELEGATE
            )
        );
        account.addDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader() public {
        account.addDelegate({_delegate: DELEGATE});
        account.removeDelegate({_delegate: DELEGATE});
        assert(!account.delegates(DELEGATE));
    }

    function test_RemoveDelegatedTrader_Event() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectEmit(true, true, true, true);
        emit DelegatedAccountRemoved(address(this), DELEGATE);
        account.removeDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader_OnlyOwner() public {
        account.addDelegate({_delegate: DELEGATE});
        account.transferOwnership(KWENTA_TREASURY);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.removeDelegate({_delegate: DELEGATE});
    }

    function test_RemoveDelegatedTrader_ZeroAddress() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, address(0)
            )
        );
        account.removeDelegate({_delegate: address(0)});
    }

    function test_RemoveDelegatedTrader_NotDelegated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Auth.InvalidDelegateAddress.selector, DELEGATE
            )
        );
        account.removeDelegate({_delegate: DELEGATE});
    }

    /*//////////////////////////////////////////////////////////////
                      DELEGATED TRADER PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function test_DelegatedTrader_TransferAccountOwnership() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        account.transferOwnership(DELEGATE);
    }

    /*//////////////////////////////////////////////////////////////
                           COMMAND EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The following commands *ARE NOT* allowed to be executed by a Delegate
     * @dev All commands can be executed by the owner and this behavior is tested in
     * test/integration/margin.behavior.t.sol and test/integration/order.behavior.t.sol
     */

    function test_DelegatedTrader_Execute_ACCOUNT_MODIFY_MARGIN() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);

        /// @notice delegate CANNOT execute the following COMMAND
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        modifyAccountMargin(int256(AMOUNT));
    }

    function test_DelegatedTrader_Execute_ACCOUNT_WITHDRAW_ETH() public {
        account.addDelegate({_delegate: DELEGATE});
        vm.prank(DELEGATE);

        /// @notice delegate CANNOT execute the following COMMAND
        vm.expectRevert(abi.encodeWithSelector(Auth.Unauthorized.selector));
        withdrawEth(AMOUNT);
    }

    /**
     * @notice The following commands *ARE* allowed to be executed by a Delegate
     * @dev All commands can be executed by the owner and this behavior is tested in
     * test/integration/margin.behavior.t.sol and test/integration/order.behavior.t.sol
     */

    function test_DelegatedTrader_Execute_PERPS_V2_MODIFY_MARGIN() public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        inputs[0] =
            abi.encode(getMarketAddressFromKey(sETHPERP), int256(AMOUNT));

        vm.prank(DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientFreeMargin.selector, 0, AMOUNT
            )
        );

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. insufficient free margin)
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_WITHDRAW_ALL_MARGIN()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);
        vm.expectCall(
            getMarketAddressFromKey(sETHPERP),
            abi.encodeWithSelector(
                IPerpsV2MarketConsolidated.withdrawAllMargin.selector
            )
        );

        /// @notice delegate CAN execute the following COMMAND
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_ATOMIC_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. Synthetix reverts due to empty order)
        vm.expectRevert("Cannot submit empty order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CLOSE_POSITION() public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("No position open");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0, 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("no existing position");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] =
            IAccount.Command.PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP), 0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. No position in Synthetix market to close)
        vm.expectRevert("no existing position");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_DELAYED_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CANCEL_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no previous order in Synthetix market)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER(
    ) public {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;
        inputs[0] = abi.encode(getMarketAddressFromKey(sETHPERP));

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no previous order in Synthetix market)
        vm.expectRevert("no previous order");
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_GELATO_PLACE_CONDITIONAL_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        inputs[0] = abi.encode(
            sETHPERP, 0, 0, 0, IAccount.ConditionalOrderTypes.LIMIT, 0, false
        );

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.ValueCannotBeZero.selector, bytes32("_sizeDelta")
            )
        );
        account.execute(commands, inputs);
    }

    function test_DelegatedTrader_Execute_GELATO_CANCEL_CONDITIONAL_ORDER()
        public
    {
        account.addDelegate({_delegate: DELEGATE});

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        bytes[] memory inputs = new bytes[](1);

        commands[0] = IAccount.Command.GELATO_CANCEL_CONDITIONAL_ORDER;
        inputs[0] = abi.encode(0);

        vm.prank(DELEGATE);

        /// @notice delegate CAN execute the following COMMAND
        /// @dev execute will fail for other reasons (e.g. no task exists with id 0)
        vm.expectRevert("Automate.cancelTask: Task not found");
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                             MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    function test_Abs(int256 x) public view {
        if (x == 0) {
            assert(accountExposed.expose_abs(x) == 0);
        } else {
            assert(accountExposed.expose_abs(x) > 0);
        }
    }

    function test_IsSameSign(int256 x, int256 y) public {
        if (x == 0 || y == 0) {
            vm.expectRevert();
            accountExposed.expose_isSameSign(x, y);
        } else if (x > 0 && y > 0) {
            assert(accountExposed.expose_isSameSign(x, y));
        } else if (x < 0 && y < 0) {
            assert(accountExposed.expose_isSameSign(x, y));
        } else if (x > 0 && y < 0) {
            assert(!accountExposed.expose_isSameSign(x, y));
        } else if (x < 0 && y > 0) {
            assert(!accountExposed.expose_isSameSign(x, y));
        } else {
            assert(false);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
        // market and order related params
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
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }
}
