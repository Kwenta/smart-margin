// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount, IFuturesMarketManager, IPerpsV2MarketConsolidated} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {ISynth} from "@synthetix/ISynth.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";

contract AccountTest is Test {
    /// @notice BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
    /// @dev hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER = 60242268;

    Settings private settings;
    Events private events;
    Factory private factory;
    ERC20 private sUSD;

    uint256 private constant AMOUNT = 10_000 ether;

    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    uint256 private tradeFee = 1;
    uint256 private limitOrderFee = 2;
    uint256 private stopOrderFee = 3;

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

    receive() external payable {}

    function setUp() public {
        // select block number
        vm.rollFork(BLOCK_NUMBER);

        sUSD = ERC20(ADDRESS_RESOLVER.getAddress("ProxyERC20sUSD"));

        // uses deployment script for tests (2 birds 1 stone)
        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: tradeFee,
            limitOrderFee: limitOrderFee,
            stopOrderFee: stopOrderFee
        });

        settings = Settings(factory.settings());
        events = Events(factory.events());
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanFetchFreeMargin() external {
        Account account = createAccount();
        assert(account.freeMargin() == 0);
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
        account.deposit(AMOUNT);
        assert(account.freeMargin() == AMOUNT);
        account.withdraw(AMOUNT);
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
        address issuer = ADDRESS_RESOLVER.getAddress("Issuer");
        ISynth synthsUSD = ISynth(ADDRESS_RESOLVER.getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    // @HELPER
    /// @notice create margin base account
    /// @return account - Account account
    function createAccount() private returns (Account account) {
        account = Account(payable(factory.newAccount()));
    }

    // @HELPER
    /// @notice create margin base account and fund it with sUSD
    /// @return Account account
    function createAccountAndDepositSUSD() private returns (Account) {
        Account account = createAccount();
        mintSUSD(address(this), AMOUNT);
        sUSD.approve(address(account), AMOUNT);
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
