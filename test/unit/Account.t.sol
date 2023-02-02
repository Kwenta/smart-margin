// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "@solmate/tokens/ERC20.sol";
import "@synthetix/ISynth.sol";
import "@synthetix/IAddressResolver.sol";
import "@synthetix/IPerpsV2MarketSettings.sol";
import "../../src/Settings.sol";
import "../../src/interfaces/ISettings.sol";
import "../../src/Factory.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/Account.sol";
import "../../src/interfaces/IAccount.sol";

contract AccountTest is Test {
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
        IAccount.OrderTypes orderType,
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

    Settings private settings;
    Factory private factory;
    ERC20 private sUSD;

    receive() external payable {}

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        // establish sUSD address
        sUSD = ERC20(ADDRESS_RESOLVER.getAddress("ProxyERC20sUSD"));

        settings = new Settings({
            _owner: address(this),
            _treasury: KWENTA_TREASURY,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_LOSS_FEE
        });

        address implementation = address(new Account());

        factory = new Factory({
            _owner: address(this),
            _marginAsset: address(sUSD),
            _addressResolver: address(ADDRESS_RESOLVER),
            _settings: address(settings),
            _ops: payable(GELATO_OPS),
            _implementation: implementation
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice test fetching free margin
    function testCanFetchFreeMargin() external {
        // call factory to create account
        Account account = createAccount();

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
    /// @return account - Account account
    function createAccount() private returns (Account account) {
        // call factory to create account
        account = Account(payable(factory.newAccount()));
    }

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return Account account
    function createAccountAndDepositSUSD() private returns (Account) {
        // call factory to create account
        Account account = createAccount();

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
