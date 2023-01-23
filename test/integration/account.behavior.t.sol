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

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract AccountBehaviorTest is Test {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    /// @notice max BPS; used for decimals calculations
    uint256 private constant MAX_BPS = 10000;

    /// @notice max uint256
    uint256 MAX_INT = 2**256 - 1;

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

    /// @notice test only owner can deposit sUSD into account
    function testOnlyOwnerCanDepositSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // expect revert
        vm.expectRevert("Ownable: caller is not the owner");

        // deposit sUSD into account
        account.deposit(AMOUNT);
    }

    /// @notice deposit sUSD into account
    function testDepositSUSD(uint256 x) external {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // check account has no sUSD
        assert(sUSD.balanceOf(address(account)) == 0);

        if (x == 0) {
            // expect revert
            bytes32 valueName = "_amount";
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarginBase.ValueCannotBeZero.selector,
                    valueName
                )
            );

            // attempt to deposit zero sUSD into account
            account.deposit(x);
        } else if (x > AMOUNT) {
            // expect revert
            vm.expectRevert();

            // deposit sUSD into account
            account.deposit(x);
        } else {
            // check deposit event emitted
            vm.expectEmit(true, false, false, true);
            emit Deposit(address(this), x);

            // deposit sUSD into account
            account.deposit(x);

            // check account has sUSD
            assert(sUSD.balanceOf(address(account)) == x);
        }
    }

    /// @notice test only owner can withdraw sUSD from account
    function testOnlyOwnerCanWithdrawSUSD() external {
        // call factory to create account
        MarginBase account = createAccount();

        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // expect revert
        vm.expectRevert("Ownable: caller is not the owner");

        // withdraw sUSD from account
        account.withdraw(AMOUNT);
    }

    /// @notice withdraw sUSD from account
    function testWithdrawSUSD(uint256 x) external {
        // call factory to create account
        MarginBase account = createAccount();

        // mint sUSD and transfer to this address
        mintSUSD(address(this), AMOUNT);

        // approve account to spend AMOUNT
        sUSD.approve(address(account), AMOUNT);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        if (x == 0) {
            // expect revert
            bytes32 valueName = "_amount";
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarginBase.ValueCannotBeZero.selector,
                    valueName
                )
            );

            // attempt to withdraw zero sUSD from account
            account.withdraw(x);
        } else if (x > AMOUNT) {
            // expect revert
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarginBase.InsufficientFreeMargin.selector,
                    AMOUNT,
                    x
                )
            );

            // withdraw sUSD
            account.withdraw(x);
        } else {
            // check withdraw event emitted
            vm.expectEmit(true, false, false, true);
            emit Withdraw(address(this), x);

            // withdraw sUSD from account
            account.withdraw(x);

            // check this address has sUSD
            assert(sUSD.balanceOf(address(this)) == x);

            // check account sUSD balance has decreased
            assert(sUSD.balanceOf(address(account)) == AMOUNT - x);
        }
    }

    /// @notice test only owner can deposit ETH into account
    function testOnlyOwnerCanDepositETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // expect revert
        vm.expectRevert("Ownable: caller is not the owner");

        // try to deposit ETH into account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);
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

    /// @notice test only owner can withdraw ETH from account
    function testOnlyOwnerCanWithdrawETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // transfer ownership to another address
        account.transferOwnership(KWENTA_TREASURY);

        // expect revert
        vm.expectRevert("Ownable: caller is not the owner");

        // try to withdraw ETH
        account.withdrawEth(1 ether);
    }

    function testWithdrawEth(uint256 x) external {
        // call factory to create account
        MarginBase account = createAccount();

        // send ETH to account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        // check account has ETH
        uint256 balance = address(account).balance;
        assert(balance == 1 ether);

        if (x > 1 ether) {
            // expect revert
            vm.expectRevert(IMarginBase.EthWithdrawalFailed.selector);

            // withdraw ETH
            account.withdrawEth(x);
        } else if (x == 0) {
            // expect revert
            bytes32 valueName = "_amount";
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarginBase.ValueCannotBeZero.selector,
                    valueName
                )
            );

            // withdraw ETH
            account.withdrawEth(x);
        } else {
            // check EthWithdraw event emitted
            vm.expectEmit(true, false, false, true);
            emit EthWithdraw(address(this), x);

            // withdraw ETH
            account.withdrawEth(x);

            // check account lost x ETH
            assert(address(account).balance == balance - x);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

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

        // withdraw all sUSD from account
        account.withdraw(AMOUNT);

        // expect free margin to be zero
        assert(account.freeMargin() == 0);
    }

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

    /// @notice test if an order can be executed
    function canCheckIfOrderCanBeExecuted() external {
        // @TODO checker()
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTE
    //////////////////////////////////////////////////////////////*/

    /// @notice test providing non-matching command and input lengths
    function testCannotProvideNonMatchingCommandAndInputLengths() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;

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

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    /// @notice test invalid command
    function testCannotExecuteInvalidCommand() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define calldata
        bytes memory dataWithInvalidCommand = abi.encodeWithSignature(
            "execute(uint256,bytes)",
            69, // enums are rep as uint256 and there are not enough commands to reach 69
            abi.encode(address(0))
        );

        // expect revert (69 is the uint256 value for the invalid enum)
        vm.expectRevert(
            abi.encodeWithSelector(IMarginBase.InvalidCommandType.selector, 69)
        );

        // call execute
        (bool s, ) = address(account).call(dataWithInvalidCommand);
        assert(!s);
    }

    // @AUDITOR increased scrutiny requested for invalid inputs.
    /// @notice test invalid input with valid command
    function testFailExecuteInvalidInputWithValidCommand() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;

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
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

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
        MarginBase account = createAccountAndDepositSUSD();

        // get account margin balance
        uint256 accountBalance = sUSD.balanceOf(address(account));

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, fuzzedMarginDelta);

        /// @dev define & test outcomes:

        // outcome 1: margin delta cannot be zero
        if (fuzzedMarginDelta == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(IMarginBase.InvalidMarginDelta.selector)
            );
            account.execute(commands, inputs);
        }

        // outcome 2: margin delta is positive; thus a deposit
        if (fuzzedMarginDelta > 0) {
            if (fuzzedMarginDelta > int256(accountBalance)) {
                // outcome 2.1: margin delta larger than what is available in account
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IMarginBase.InsufficientFreeMargin.selector,
                        accountBalance,
                        fuzzedMarginDelta
                    )
                );
                account.execute(commands, inputs);
            } else {
                // outcome 2.2: margin delta deposited into market
                account.execute(commands, inputs);
                IPerpsV2MarketConsolidated.Position memory position = account
                    .getPosition(sETHPERP);
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
        MarginBase account = createAccountAndDepositSUSD();

        // get account margin balance
        int256 balance = int256(sUSD.balanceOf(address(account)));

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;

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
            vm.expectRevert(
                abi.encodeWithSelector(IMarginBase.InvalidMarginDelta.selector)
            );
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
                IPerpsV2MarketConsolidated.Position memory position = account
                    .getPosition(sETHPERP);
                assert(
                    int256(uint256(position.margin)) ==
                        balance + fuzzedMarginDelta
                );
                assert(
                    sUSD.balanceOf(address(account)) == abs(fuzzedMarginDelta)
                );
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
        MarginBase account = createAccountAndDepositSUSD();

        // get account margin balance
        uint256 preBalance = sUSD.balanceOf(address(account));

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;

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
        MarginBase account = createAccountAndDepositSUSD();

        // get account margin balance
        uint256 preBalance = sUSD.balanceOf(address(account));

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, int256(AMOUNT));

        // call execute
        account.execute(commands, inputs);

        // define commands
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_WITHDRAW_ALL_MARGIN;

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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
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

    /*
        PERPS_V2_CANCEL_DELAYED_ORDER
    */

    /// @notice test attempting to cancel a delayed order when none exists
    /// @dev test command: PERPS_V2_CANCEL_DELAYED_ORDER
    function testCancelDelayedOrderWhenNoneExists() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_CANCEL_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // expect revert
        vm.expectRevert("no previous order");

        // call execute
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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
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

        // define commands
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_CANCEL_DELAYED_ORDER;

        // define inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

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

    /*
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    */

    /// @notice test attempting to cancel an off-chain delayed order when none exists
    /// @dev test command: PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    function testCancelOffchainDelayedOrderWhenNoneExists() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);

        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes
            .Command
            .PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // expect revert
        vm.expectRevert("no previous order");

        // call execute
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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IMarginBaseTypes
            .Command
            .PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;

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
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes
            .Command
            .PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER;

        // define inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market);

        // call execute
        account.execute(commands, inputs);

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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_CLOSE_POSITION;

        // // define inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // expect revert
        vm.expectRevert();

        // call execute
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
        MarginBase account = createAccountAndDepositSUSD();

        // define commands
        IMarginBaseTypes.Command[]
            memory commands = new IMarginBaseTypes.Command[](2);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IMarginBaseTypes.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;

        // define inputs
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // redefine commands
        commands = new IMarginBaseTypes.Command[](1);
        commands[0] = IMarginBaseTypes.Command.PERPS_V2_CLOSE_POSITION;

        // redefine inputs
        inputs = new bytes[](1);
        inputs[0] = abi.encode(market, priceImpactDelta);

        // call execute
        account.execute(commands, inputs);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // expect size to be zero and margin to be non-zero
        assert(position.size == 0);
        assert(position.margin != 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TRADING FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice test trading fee calculation
    /// @param fuzzedSizeDelta: fuzzed size delta
    function testCalculateTradeFee(int128 fuzzedSizeDelta) external {
        // advanced order fee
        uint256 advancedOrderFee = MAX_BPS / 99; // 1% fee

        // define market
        IPerpsV2MarketConsolidated market = IPerpsV2MarketConsolidated(
            getMarketAddressFromKey(sETHPERP)
        );

        // call factory to create account
        MarginBase account = createAccount();

        // calculate expected fee
        uint256 percentToTake = marginBaseSettings.tradeFee() +
            advancedOrderFee;
        uint256 fee = (abs(int256(fuzzedSizeDelta)) * percentToTake) / MAX_BPS;
        (uint256 price, bool invalid) = market.assetPrice();
        assert(!invalid);
        uint256 feeInSUSD = (price * fee) / 1e18;

        // call calculateTradeFee()
        uint256 actualFee = account.calculateTradeFee({
            _sizeDelta: fuzzedSizeDelta,
            _market: market,
            _advancedOrderFee: advancedOrderFee
        });

        assertEq(actualFee, feeInSUSD);
    }

    /// @notice test trading fee is imposed when size delta is non-zero
    function testTradeFeeImposedWhenSizeDeltaNonZero() external {
        // @TODO test fee transfer
        // @TODO test FeeImposed event
    }

    /// @notice test CannotPayFee error is emitted when fee exceeds free margin
    function testTradeFeeCannotExceedFreeMargin() external {
        // @TODO test CannotPayFee error
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
        address issuer = ADDRESS_RESOLVER.getAddress("Issuer");
        ISynth synthsUSD = ISynth(ADDRESS_RESOLVER.getAddress("SynthsUSD"));

        // set caller as issuer
        vm.prank(issuer);

        // mint sUSD
        synthsUSD.issue(to, amount);
    }

    // @HELPER
    /// @notice create margin base account
    /// @return account - MarginBase account
    function createAccount() private returns (MarginBase account) {
        // call factory to create account
        account = MarginBase(payable(marginAccountFactory.newAccount()));
    }

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

    // @HELPER
    /// @notice takes int and returns absolute value uint
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
