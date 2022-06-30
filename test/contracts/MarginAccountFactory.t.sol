// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginBaseSettings.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;

    address private addressResolver =
        0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C;

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
        uint256 distributionFee = 5; // 5 BPS
        marginBaseSettings = new MarginBaseSettings(distributionFee);

        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(0),
            addressResolver,
            address(marginBaseSettings)
        );
    }

    function testAccountCreation() public {
        address account = marginAccountFactory.newAccount();
        assertTrue(account != address(0));
    }

    // Assert proxy is less than implementation
    function testAssertProxySize() public {
        address account = marginAccountFactory.newAccount();
        assertEq(account.code.length, 45); // Minimal proxy is 45 bytes
        assertLt(
            account.code.length,
            address(marginAccountFactory.implementation()).code.length
        );
    }

    function testAccountOwnerIsMsgSender() public {
        MarginBase account = MarginBase(marginAccountFactory.newAccount());
        assertEq(account.owner(), address(this));
    }
}
