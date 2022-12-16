// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "@solmate/tokens/ERC20.sol";
import "../../src/MarginBaseSettings.sol";
import "../../src/MarginAccountFactory.sol";
import "../../src/MarginAccountFactoryStorage.sol";
import "../../src/MarginBase.sol";
import "../../src/interfaces/IAddressResolver.sol";

contract AccountBehaviorTest is Test {
    uint256 private constant BLOCK_NUMBER = 16000000;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // synthetix (ReadProxyAddressResolver)
    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    // gelato
    address private constant GELATO_OPS =
        0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

    // kwenta treasury multisig
    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    /// @notice fee settings
    uint256 private constant TRADE_FEE = 5; // 5 BPS
    uint256 private constant LIMIT_ORDER_FEE = 5; // 5 BPS
    uint256 private constant STOP_LOSS_FEE = 10; // 10 BPS

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
    function testAccountCreated() external {
        // call factory to create account
        MarginBase account = createAccount();

        // check account address exists
        assert(address(account) != address(0));

        // check correct values set in constructor
        assert(address(account.addressResolver()) == address(ADDRESS_RESOLVER));
        assert(
            address(account.futuresManager()) ==
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

    /// @dev utility function doing same as above
    /// @return account - MarginBase account
    function createAccount() private returns (MarginBase account) {
        // call factory to create account
        account = MarginBase(payable(marginAccountFactory.newAccount()));
    }

    /*//////////////////////////////////////////////////////////////
                       ACCOUNT DEPOSITS/WITHDRAWS
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit sUSD into account
    function testDeposit() external {}

    /// @notice withdraw sUSD from account
    function testWithdraw() external {}

    /*//////////////////////////////////////////////////////////////
                             BASIC TRADING
    //////////////////////////////////////////////////////////////*/
    /// @dev basic trading excludes advanced/conditional 
    /// orders such as limit/stop-loss

    ///
    /// OPENING POSITIONS
    ///

    /// @notice open a single long position
    function testOpenLongPosition() external {}

    /// @notice open multiple long positions
    function testOpenLongPositions() external {}

    /// @notice open a single short position
    function testOpenShortPosition() external {}

    /// @notice open multiple short positions
    function testOpenShortPositions() external {}

    /// @notice open multiple long and short positions
    function testOpenPositions() external {}

    ///
    /// CLOSING POSITIONS
    ///

    /// @notice close a single long position
    function testCloseLongPosition() external {}

    /// @notice close multiple long positions
    function testCloseLongPositions() external {}

    /// @notice close a single short position
    function testCloseShortPosition() external {}

    /// @notice close multiple short positions
    function testCloseShortPositions() external {}

    /// @notice open multiple long and short positions
    function testClosePositions() external {}

    ///
    /// MODIFYING POSITION MARGIN
    ///

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
    function testModifyMultiplePositionsMargin() external {}
}
