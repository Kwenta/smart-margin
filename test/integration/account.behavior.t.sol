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

        // get position details
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

    /// @notice submit offchain delayed order
    function testSubmitOffchainDelayedOrder() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define position details
        IMarginBaseTypes.NewPosition memory longPosition = IMarginBaseTypes
            .NewPosition({
                marketKey: sETHPERP,
                marginDelta: int256(AMOUNT) / 10,
                sizeDelta: 1 ether,
                priceImpactDelta: 1
            });

        // define positions array
        IMarginBaseTypes.NewPosition[]
            memory positions = new IMarginBaseTypes.NewPosition[](1);
        positions[0] = longPosition;

        /// @dev SUBMIT ORDER

        // place trade
        account.distributeMargin(positions);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // expect only margin to be non-zero since order has not been executed
        assert(position.id == 0);
        assert(position.lastFundingIndex == 0);
        assert(position.margin != 0);
        assert(position.lastPrice == 0);
        assert(position.size == 0);
    }

    /// @notice submit and then execute offchain delayed order
    function testExecuteOffchainDelayedOrder() external {
        // get account for trading
        MarginBase account = createAccountAndDepositSUSD();

        // define position details
        IMarginBaseTypes.NewPosition memory longPosition = IMarginBaseTypes
            .NewPosition({
                marketKey: sETHPERP,
                marginDelta: int256(AMOUNT) / 10,
                sizeDelta: 1 ether,
                priceImpactDelta: 1
            });

        // define positions array
        IMarginBaseTypes.NewPosition[]
            memory positions = new IMarginBaseTypes.NewPosition[](1);
        positions[0] = longPosition;

        /// @dev SUBMIT ORDER

        // place trade
        account.distributeMargin(positions);

        // get position details
        IPerpsV2MarketConsolidated.Position memory position = account
            .getPosition(sETHPERP);

        // @TODO fetch delayed order and check details

        /// @dev EXECUTE ORDER

        /* @TODO

        // adjust Synthetix PerpsV2 sETHPERP Market Settings as contract owner
        address marketSettings = ADDRESS_RESOLVER.getAddress(
            "PerpsV2MarketSettings"
        );

        // determine min age order must be to allow execution
        uint256 minAge = IPerpsV2MarketSettings(marketSettings)
            .offchainDelayedOrderMinAge(sETHPERP);

        // increase time passed
        vm.warp(minAge + 1);

        // generate authentic price-feed to submit
        bytes[] memory priceUpdateData;

        // attempt to execute order
        // ADDRESS_RESOLVER: 0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C
        // FuturesMarketManager: 0xdb89f3fc45A707Dd49781495f77f8ae69bF5cA6e
        IFuturesMarketManager manager = IFuturesMarketManager(
            ADDRESS_RESOLVER.getAddress("FuturesMarketManager")
        );
        // (ProxyPerpsV2) sETHPERP: 0x2B3bb4c683BFc5239B029131EEf3B1d214478d93::dfa723cc
        IPerpsV2MarketConsolidated market = IPerpsV2MarketConsolidated(
            manager.marketForKey(sETHPERP)
        );
        // PerpsV2MarketDelayedOrdersOffchain: 0x36841F7Ff6fBD318202A5101F8426eBb051d5e4d
        // PerpsV2MarketState: 0x038dC05D68ED32F23e6856c0D44b0696B325bfC8
        // PerpsV2ExchangeRate: 0x4aD2d14Bed21062Ef7B85C378F69cDdf6ED7489C
        // FlexibleStorage: 0x47649022380d182DA8010Ae5d257fea4227b21ff
        // ERC1967Proxy: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
        // PythUpgradable: 0x47C409845b57BA4004c26A5841e59Dc15BB39E7b
        market.executeOffchainDelayedOrder{value: 1 ether}(address(account), priceUpdateData);
        
        */
    }

    /// @notice close long and short positions
    function testClosePositions() external {}

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
