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

        assert(sUSD.balanceOf(address(account)) == 0);

        // deposit sUSD into account
        account.deposit(AMOUNT);

        assert(sUSD.balanceOf(address(account)) == AMOUNT);
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

        // withdraw sUSD from account
        account.withdraw(AMOUNT);

        assert(sUSD.balanceOf(address(this)) == AMOUNT);
        assert(sUSD.balanceOf(address(account)) == 0);
    }

    /// @notice withdraw ETH from account
    function testWithdrawETH() external {
        // call factory to create account
        MarginBase account = createAccount();

        // send ETH to account
        (bool s, ) = address(account).call{value: 1 ether}("");
        assert(s);

        assert(address(account).balance == 1 ether);

        // withdraw ETH
        account.withdrawEth(1 ether);

        assert(address(account).balance == 0);
    }

    /*//////////////////////////////////////////////////////////////
                    FETCHING ORDER/POSITION DETAILS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                             BASIC TRADING
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

    /// @notice submit atomic order
    function testSubmitAtomicOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 10 ether;

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

    function testSubmitDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 10 ether;
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

    function testSubmitOffchainDelayedOrder() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 10 ether;

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

    /// @notice close position
    function testClosePosition() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 10 ether;

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
        inputs[0] = abi.encode(market, 0);

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

    function testClosingPositionReturnsMarginToAccount() external {
        // market and order related params
        address market = getMarketAddressFromKey(sETHPERP);
        int256 marginDelta = int256(AMOUNT) / 10;
        int256 sizeDelta = 1 ether;
        uint256 priceImpactDelta = 10 ether;

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
        inputs[0] = abi.encode(market, 0);

        // call execute
        account.execute(commands, inputs);

        // establish account margin balance post-trades
        uint256 postBalance = sUSD.balanceOf(address(account));

        // confirm post balance is within 1% of pre balance
        assertApproxEqAbs(preBalance, postBalance, preBalance / 100);
    }

    /// @notice open a single long position and then add margin
    /// @param x: fuzzed value respresenting amount of margin to add
    function testAddMarginToLong(uint256 x) external {}

    /// @notice open a single short position and then add margin
    /// @param x: fuzzed value respresenting amount of margin to add
    function testAddMarginToShort(uint256 x) external {}

    /// @notice open a single long position and then withdraw margin
    /// @param x: fuzzed value respresenting amount of margin to withdraw
    function testWithdrawMarginFromLong(uint256 x) external {}

    /// @notice open a single short position and then withdraw margin
    /// @param x: fuzzed value respresenting amount of margin to withdraw
    function testWithdrawMarginFromShort(uint256 x) external {}

    /// @notice open a single long position and attempt to withdraw all margin
    function testRemoveAllMarginFromLong() external {}

    /// @notice open a single short position and attempt to withdraw all margin
    function testRemoveAllMarginFromShort() external {}

    /// @notice open long and short positions in different markets
    /// and in a single trade:
    /// (1) + margin to some positions
    /// (2) - margin from some positions
    function testModifyMultiplePositionsMargin() external {}

    ///
    /// MODIFYING POSITION SIZE
    ///

    /// @notice open a single long position and then increase size
    /// @param x: fuzzed value respresenting size increase
    function testIncSizeOfLong(uint256 x) external {}

    /// @notice open a single short position and then increase size
    /// @param x: fuzzed value respresenting size increase
    function testIncSizeOfShort(uint256 x) external {}

    /// @notice open a single long position and then decrease size
    /// @param x: fuzzed value respresenting size decrease
    function testDecSizeOfLong(uint256 x) external {}

    /// @notice open a single short position and then decrease size
    /// @param x: fuzzed value respresenting size decrease
    function testDecSizeOfShort(uint256 x) external {}

    /// @notice open a single long position and attempt to decrease
    /// size to zero
    function testDecSizeToZeroOfLong() external {}

    /// @notice open a single short position and attempt to decrease
    /// size to zero
    function testDecSizeToZeroOfShort() external {}

    /// @notice open long and short positions in different markets
    /// and in a single trade:
    /// (1) + size of some positions
    /// (2) - size of some positions
    function testModifyMultiplePositionsSize() external {}
}
