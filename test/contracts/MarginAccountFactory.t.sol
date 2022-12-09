// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginBaseSettings.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginAccountFactoryStorage.sol";
import "../../contracts/MarginBase.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;
    MarginAccountFactoryStorage private marginAccountFactoryStorage;

    address private addressResolver =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;

    address private constant KWENTA_TREASURY =
        0x82d2242257115351899894eF384f779b5ba8c695;

    // futures market manager for mocking
    IFuturesMarketManager private futuresManager =
        IFuturesMarketManager(0xc704c9AA89d1ca60F67B3075d05fBb92b3B00B3B);

    /**
     * Mocking AddressResolver.sol
     *
     * @notice mock requireAndGetAddress (which returns futuresManager address)
     * @dev Mocked calls are in effect until clearMockedCalls is called.
     */
    function mockAddressResolverCalls() internal {
        bytes32 futuresManagerKey = "FuturesMarketManager";

        // @mock addressResolver.requireAndGetAddress()
        cheats.mockCall(
            address(addressResolver),
            abi.encodeWithSelector(
                IAddressResolver.requireAndGetAddress.selector,
                futuresManagerKey,
                "MarginBase: Could not get Futures Market Manager"
            ),
            abi.encode(address(futuresManager))
        );
    }

    function setUp() public {
        mockAddressResolverCalls();

        /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
        uint256 tradeFee = 5; // 5 BPS
        uint256 limitOrderFee = 5; // 5 BPS
        uint256 stopLossFee = 10; // 10 BPS
        marginBaseSettings = new MarginBaseSettings({
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopLossFee
        });

        marginAccountFactoryStorage = new MarginAccountFactoryStorage({
            _owner: address(this)
        });

        marginAccountFactory = new MarginAccountFactory({
            _store: address(marginAccountFactoryStorage),
            _marginAsset: address(0),
            _addressResolver: addressResolver,
            _marginBaseSettings: address(marginBaseSettings),
            _ops: payable(address(0))
        });
    }

    function testOwnerCanAddFactory() public {
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
        assertTrue(
            marginAccountFactoryStorage.verifiedFactories(
                address(marginAccountFactory)
            )
        );
    }

    function testNonOwnerCannotAddFactory() public {
        cheats.expectRevert("Ownable: caller is not the owner");
        cheats.prank(address(0));
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
    }

    function testNonVerifiedFactoryCannotCreate() public {
        cheats.expectRevert(
            abi.encodeWithSelector(
                MarginAccountFactoryStorage.FactoryOnly.selector
            )
        );
        marginAccountFactory.newAccount();
    }

    function testAccountCreation() public {
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
        address account = marginAccountFactory.newAccount();
        assertTrue(account != address(0));
        assertTrue(
            marginAccountFactoryStorage.deployedMarginAccounts(address(this)) ==
                address(account)
        );
    }

    // Assert proxy is less than implementation
    function testAssertProxySize() public {
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
        address account = marginAccountFactory.newAccount();
        assertEq(account.code.length, 45); // Minimal proxy is 45 bytes
        assertLt(
            account.code.length,
            address(marginAccountFactory.implementation()).code.length
        );
    }

    function testAccountOwnerIsMsgSender() public {
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
        MarginBase account = MarginBase(marginAccountFactory.newAccount());
        assertEq(account.owner(), address(this));
    }

    function testCannotInitAccountTwice() public {
        marginAccountFactoryStorage.addVerifiedFactory(
            address(marginAccountFactory)
        );
        MarginBase account = MarginBase(
            payable(marginAccountFactory.newAccount())
        );
        cheats.expectRevert();
        account.initialize(
            address(0),
            address(0),
            address(0),
            payable(address(0))
        );
    }
}
