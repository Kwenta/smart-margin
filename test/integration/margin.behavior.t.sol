// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../src/MarginBaseSettings.sol";
import "../../src/MarginAccountFactory.sol";
import "../../src/MarginAccountFactoryStorage.sol";
import "../../src/MarginBase.sol";

contract MarginBehaviorTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice static addresses
    address private constant addressResolver =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address private constant KWENTA_TREASURY =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    IFuturesMarketManager private constant futuresManager =
        IFuturesMarketManager(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Kwenta contracts
    MarginBaseSettings private marginBaseSettings;
    MarginAccountFactory private marginAccountFactory;
    MarginAccountFactoryStorage private marginAccountFactoryStorage;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Important to keep in mind that all test functions are isolated,
    /// meaning each test function is executed with a copy of the state after
    /// setUp and is executed in its own stand-alone EVM.
    function setUp() public {
        // fee(s)
        uint256 tradeFee = 5; // 5 BPS
        uint256 limitOrderFee = 5; // 5 BPS
        uint256 stopLossFee = 10; // 10 BPS

        // deploy settings
        marginBaseSettings = new MarginBaseSettings({
            _treasury: KWENTA_TREASURY,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopLossFee
        });

        // deploy storage
        marginAccountFactoryStorage = new MarginAccountFactoryStorage({
            _owner: address(this)
        });

        // deploy factory
        marginAccountFactory = new MarginAccountFactory({
            _store: address(marginAccountFactoryStorage),
            _marginAsset: address(0),
            _addressResolver: addressResolver,
            _marginBaseSettings: address(marginBaseSettings),
            _ops: payable(address(0))
        });
    }
}
