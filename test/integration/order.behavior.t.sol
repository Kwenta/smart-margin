// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../src/MarginBaseSettings.sol";
import "../../src/MarginAccountFactory.sol";
import "../../src/MarginAccountFactoryStorage.sol";
import "../../src/MarginBase.sol";

contract OrderBehaviorTest is Test {
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;
    MarginAccountFactoryStorage private marginAccountFactoryStorage;
    address private addressResolver =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address private constant KWENTA_TREASURY =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    IFuturesMarketManager private futuresManager =
        IFuturesMarketManager(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    function setUp() public {
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
}
