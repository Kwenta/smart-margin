// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "@solmate/tokens/ERC20.sol";
import "@synthetix/ISynth.sol";
import "@synthetix/IAddressResolver.sol";
import "@synthetix/IPerpsV2MarketSettings.sol";
import "../../src/MarginBaseSettings.sol";
import "../../src/MarginAccountFactory.sol";
import "../../src/MarginAccountFactoryStorage.sol";
import "../../src/MarginBase.sol";
import "../../src/interfaces/IMarginBaseTypes.sol";

// Functions tagged with @HELPER are helper functions and not tests
contract AccountBehaviorTest is Test {
    receive() external payable {}

    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    // test amount used throughout tests
    uint256 private constant AMOUNT = 10_000 ether;

    // synthetix (ReadProxyAddressResolver)
    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    // gelato
    address private constant GELATO_OPS =
        0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

    // kwenta treasury multisig
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    // fee settings
    uint256 private constant TRADE_FEE = 5; // 5 BPS
    uint256 private constant LIMIT_ORDER_FEE = 5; // 5 BPS
    uint256 private constant STOP_LOSS_FEE = 10; // 10 BPS

    // Synthetix PerpsV2 market key(s)
    bytes32 private constant sETHPERP = "sETHPERP";
    bytes32 private constant sBTCPERP = "sBTCPERP";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EthWithdraw(address indexed user, uint256 amount);
    event OrderPlaced(
        address indexed account,
        uint256 orderId,
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IMarginBaseTypes.OrderTypes orderType,
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

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice KWENTA contracts
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;
    MarginAccountFactoryStorage private marginAccountFactoryStorage;

    /// @notice other contracts
    ERC20 private sUSD;

    /*//////////////////////////////////////////////////////////////
                               MINT SUSD
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
        address issuer = ADDRESS_RESOLVER.getAddress("Issuer");
        ISynth synthsUSD = ISynth(ADDRESS_RESOLVER.getAddress("SynthsUSD"));

        // set caller as issuer
        vm.prank(issuer);

        // mint sUSD
        synthsUSD.issue(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Important to keep in mind that all test functions are isolated,
    /// meaning each test function is executed with a copy of the state after
    /// setUp and is executed in its own stand-alone EVM.
    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // establish sUSD address
        sUSD = ERC20(ADDRESS_RESOLVER.getAddress("ProxyERC20sUSD"));

        // deploy settings
        marginBaseSettings = new MarginBaseSettings({
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_LOSS_FEE
        });

        // deploy storage
        marginAccountFactoryStorage = new MarginAccountFactoryStorage({
            _owner: address(this)
        });

        // deploy factory
        marginAccountFactory = new MarginAccountFactory({
            _store: address(marginAccountFactoryStorage),
            _marginAsset: address(sUSD),
            _addressResolver: address(ADDRESS_RESOLVER),
            _marginBaseSettings: address(marginBaseSettings),
            _ops: payable(GELATO_OPS)
        });

        // add factory to list of verified factories
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            ACCOUNT CREATION
    //////////////////////////////////////////////////////////////*/

    // @HELPER
    /// @notice create margin base account
    /// @return account - MarginBase account
    function createAccount() private returns (MarginBase account) {
        // call factory to create account
        account = MarginBase(payable(marginAccountFactory.newAccount()));
    }

    /// @notice create account via the MarginAccountFactory
    /// @dev also tests that state variables properly set in constructor
    function testAccountCreated() external {
        // call factory to create account
        MarginBase account = createAccount();

        // check account address exists
        assert(address(account) != address(0));

        // check correct values set in constructor
        assert(address(account.addressResolver()) == address(ADDRESS_RESOLVER));
        assert(
            address(account.futuresMarketManager()) ==
                ADDRESS_RESOLVER.getAddress("FuturesMarketManager")
        );
        assert(
            address(account.marginBaseSettings()) == address(marginBaseSettings)
        );
        assert(address(account.marginAsset()) == address(sUSD));
        assert(address(account.owner()) == address(this));
        assert(address(account.ops()) == GELATO_OPS);

        // check store was updated
        assert(
            marginAccountFactoryStorage.deployedMarginAccounts(address(this)) ==
                address(account)
        );
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    /// @notice use helper function defined in this test contract
    /// to mint sUSD
    function testCanMintSUSD() external {
        assert(sUSD.balanceOf(address(this)) == 0);

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        assert(sUSD.balanceOf(address(this)) == AMOUNT);
    }

    /// @notice deposit sUSD into account
    function testDepositSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // check account has no sUSD
        assert(sUSD.balanceOf(address(account)) == 0);

        // check deposit event emitted
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(this), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        // check account has sUSD
        assert(sUSD.balanceOf(address(account)) == AMOUNT);
    }

    /// @notice attempt to deposit zero sUSD into account
    function testCannotDepositZeroSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // expect revert
        bytes32 valueName = "_amount";
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginBase.ValueCannotBeZero.selector,
                valueName
            )
        );

        // attempt to deposit zero sUSD into account
        account.deposit(0);
    }

    /// @notice withdraw sUSD from account
    function testWithdrawSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        // check withdraw event emitted
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(this), AMOUNT);

        // withdraw sUSD from account
        account.withdraw(AMOUNT);

        // check account has no sUSD
        assert(sUSD.balanceOf(address(this)) == AMOUNT);
        assert(sUSD.balanceOf(address(account)) == 0);
    }

    /// @notice attempt to withdraw zero sUSD from account
    function testCannotWithdrawZeroSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        // expect revert
        bytes32 valueName = "_amount";
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginBase.ValueCannotBeZero.selector,
                valueName
            )
        );

        // attempt to withdraw zero sUSD from account
        account.withdraw(0);
    }

    /// @notice deposit ETH into account
    function testDepositETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // check account has no ETH
        assert(address(account).balance == 0);

        // deposit ETH into account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        // check account has ETH
        assert(address(account).balance == 1 ether);
    }

    /// @notice withdraw ETH from account
    function testWithdrawETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // send ETH to account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        // check account has ETH
        assert(address(account).balance == 1 ether);

        // check EthWithdraw event emitted
        vm.expectEmit(true, false, false, true);
        emit EthWithdraw(address(this), 1 ether);

        // withdraw ETH
        account.withdrawEth(1 ether);

        // check account has no ETH
        assert(address(account).balance == 0);
    }

    /// @notice attempt to withdraw more ETH than account has
    function testCannotWithdrawMoreETHThanAccountHas() external {
        // call factory to create account
        MarginBase account = createAccount();

        // send ETH to account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        // expect revert
        vm.expectRevert(IMarginBase.EthWithdrawalFailed.selector);

        // withdraw ETH
        account.withdrawEth(2 ether);
    }

    /// @notice attempt to withdraw zero ETH from account
    function testCannotWithdrawZeroETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // send ETH to account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        // expect revert
        bytes32 valueName = "_amount";
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginBase.ValueCannotBeZero.selector,
                valueName
            )
        );

        // withdraw ETH
        account.withdrawEth(0);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice test fetching position details
    function testCanFetchPositionDetails() external {
        // call factory to create account
        MarginBase account = createAccount();

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // expect all details to be unset
        assert(position.id == 0);
        assert(position.lastFundingIndex == 0);
        assert(position.margin == 0);
        assert(position.lastPrice == 0);
        assert(position.size == 0);
    }

    /// @notice test fetching submitted order details
    function testCanFetchDelayedOrderDetails() external {
        // call factory to create account
        MarginBase account = createAccount();

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account
            .getDelayedOrder(sETHPERP);

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

    /// @notice test fetching free margin
    function testCanFetchFreeMargin() external {
        // call factory to create account
        MarginBase account = createAccount();

        // expect free margin to be zero
        assert(account.freeMargin() == 0);

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        // expect free margin to be equal to AMOUNT
        assert(account.freeMargin() == AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                COMMANDS
    //////////////////////////////////////////////////////////////*/
    /// @dev basic trading excludes advanced/conditional
    /// orders such as limit/stop-loss

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return MarginBase account
    function createAccountAndDepositSUSD() private returns (MarginBase) {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        return account;
    }

    // @HELPER
    /// @notice get address of market
    /// @return market address
    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
        // market and order related params
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    ADDRESS_RESOLVER.getAddress("FuturesMarketManager")
                ).marketForKey(key)
            )
        );
    }

    /// @notice test providing non-matching command and input lengths
    function testCannotProvideNonMatchingCommandAndInputLengths() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(0), 0);
        inputs[1] = abi.encode(address(0), 0);

        // expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IMarginBase.LengthMismatch.selector)
        );

        // call execute
        account.execute(commands, inputs);
    }

    /// @notice test depositing margin into PerpsV2 market
    /// @dev test command: PERPS_V2_DEPOSIT
    function testDepositMarginIntoMarket() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, marginDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // confirm position margin are non-zero
        assert(position.margin != 0);
    }

    /// @notice test withdrawing margin from PerpsV2 market
    /// @dev test command: PERPS_V2_WITHDRAW
    function testWithdrawMarginFromMarket() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, marginDelta);

        // call execute
        account.execute(commands, inputs);

        // define commands
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_WITHDRAW;

        // define inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, (marginDelta * -1));

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // confirm position margin are decreased
        assert(position.margin == 0);
    }

    /// @notice test submitting atomic order
    /// @dev test command: PERPS_V2_SUBMIT_ATOMIC_ORDER
    function testSubmitAtomicOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;
        commands[1] = IMarginBaseTypes.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // confirm position details are non-zero
        assert(position.id != 0);
        assert(position.lastFundingIndex != 0);
        assert(position.margin != 0);
        assert(position.lastPrice != 0);
        assert(position.size != 0);
    }

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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;
        commands[1] = IMarginBaseTypes.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(
            market,
            sizeDelta,
            priceImpactDelta,
            desiredTimeDelta
        );

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account
            .getDelayedOrder(sETHPERP);

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

    /// @notice test submitting offchain delayed order
    /// @dev test command: PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
    function testSubmitOffchainDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;
        commands[1] = IMarginBaseTypes
            .Command
            .PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get delayed order details
        IPerpsV2MarketConsolidated.DelayedOrder memory order = account
            .getDelayedOrder(sETHPERP);

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

    /// @notice test opening and then closing a position
    /// @notice specifically test Synthetix PerpsV2 position details after closing
    /// @dev test command: PERPS_V2_EXIT
    function testClosePosition() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;
        commands[1] = IMarginBaseTypes.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // confirm position details are non-zero
        assert(position.id != 0);
        assert(position.lastFundingIndex != 0);
        assert(position.margin != 0);
        assert(position.lastPrice != 0);
        assert(position.size != 0);

        // redefine commands
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_EXIT;

        // redefine inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        position = account.getPosition(sETHPERP);

        // expect margin and size to be zero
        assert(position.id == 0);
        assert(position.lastFundingIndex == 0);
        assert(position.margin == 0);
        assert(position.lastPrice == 0);
        assert(position.size == 0);
    }

    /// @notice test opening and then closing a position
    /// @notice specifically tests that the margin is returned to the account
    /// @dev test command: PERPS_V2_EXIT
    function testClosingPositionReturnsMarginToAccount() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 1 ether / 2;

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // establish account margin balance pre-trades
        uint256 preBalance = sUSD.balanceOf(address(account));

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_DEPOSIT;
        commands[1] = IMarginBaseTypes.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // redefine commands
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_EXIT;

        // redefine inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // establish account margin balance post-trades
        uint256 postBalance = sUSD.balanceOf(address(account));

        // confirm post balance is within 1% of pre balance
        assertApproxEqAbs(preBalance, postBalance, preBalance / 100);
    }

    /// @notice test submitting a delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_DELAYED_ORDER

    /// @notice test submitting an off-chain delayed order and then cancelling it
    /// @dev test command: PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
}
