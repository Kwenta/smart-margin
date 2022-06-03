// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "ds-test/test.sol";
import "./interfaces/CheatCodes.sol";
import "../../contracts/MarginAccountFactory.sol";
import "../../contracts/MarginBase.sol";
import "./utils/MintableERC20.sol";

contract MarginAccountFactoryTest is DSTest {
    CheatCodes private cheats = CheatCodes(HEVM_ADDRESS);
    MintableERC20 private marginAsset;
    MarginAccountFactory private marginAccountFactory;
    MarginBase private account;

    // works for fork testing
    address private addressResolver =
        0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C;

    function setUp() public {
        marginAsset = new MintableERC20(address(this), 0);
        marginAccountFactory = new MarginAccountFactory(
            "0.0.0",
            address(marginAsset),
            addressResolver,
            payable(addressResolver)
        );
        account = MarginBase(marginAccountFactory.newAccount());
    }

    function testOwnership() public {
        assertEq(account.owner(), address(this));
    }

    function testExpectedMargin() public {
        assertEq(address(account.marginAsset()), address(marginAsset));
    }

    function testDeposit() public {
        uint256 amount = 10e18;
        deposit(amount);
        assertEq(marginAsset.balanceOf(address(account)), amount);
    }

    function testWithdrawal() public {
        uint256 amount = 10e18;
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    /// @dev Deposit/Withdrawal fuzz test
    function testWithdrawal(uint256 amount) public {
        deposit(amount);
        account.withdraw(amount);
        assertEq(marginAsset.balanceOf(address(account)), 0);
    }

    function testLimitValid() public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        uint256 currentPrice = 2e18;

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(account.validOrder(market));
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitValid(uint256 currentPrice) public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs greater than limit price
        cheats.assume(currentPrice <= expectedLimitPrice);

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(account.validOrder(market));
    }

    /// @notice These orders should ALWAYS be valid
    /// @dev Limit order validity fuzz test
    function testLimitInvalid(uint256 currentPrice) public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;

        // Toss out fuzz runs less than limit price
        cheats.assume(currentPrice > expectedLimitPrice);

        // Setup
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );

        mockExternalCallsForPrice(market, currentPrice);
        assertTrue(!account.validOrder(market));
    }

    function testPlaceOrder() public {
        address market = address(1);
        uint256 amount = 10e18;
        int256 orderSizeDelta = 1e18;
        uint256 expectedLimitPrice = 3e18;
        deposit(amount);
        placeLimitOrder(
            market,
            int256(amount),
            orderSizeDelta,
            expectedLimitPrice
        );
        (, , uint256 actualLimitPrice) = account.orders(market);
        assertEq(expectedLimitPrice, actualLimitPrice);
    }

    // Helpers

    function deposit(uint256 amount) internal {
        marginAsset.mint(address(this), amount);
        marginAsset.approve(address(account), amount);
        account.deposit(amount);
    }

    function placeLimitOrder(
        address market,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 limitPrice
    ) internal {
        bytes memory createTaskSelector = abi.encodePacked(
            IOps.createTask.selector
        );
        cheats.mockCall(account.ops(), createTaskSelector, abi.encode(true));
        account.placeOrder(market, marginDelta, sizeDelta, limitPrice);
    }

    function mockExternalCallsForPrice(address market, uint256 mockedPrice)
        internal
    {
        address exchangeRates = address(2);
        cheats.mockCall(
            market,
            abi.encodePacked(IFuturesMarket.baseAsset.selector),
            abi.encode("sSYNTH")
        );
        cheats.mockCall(
            addressResolver,
            abi.encodePacked(IAddressResolver.requireAndGetAddress.selector),
            abi.encode(exchangeRates)
        );
        cheats.mockCall(
            exchangeRates,
            abi.encodePacked(IExchangeRates.effectiveValue.selector),
            abi.encode(mockedPrice)
        );
    }

    // Utils

    function getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func)));
    }
}
