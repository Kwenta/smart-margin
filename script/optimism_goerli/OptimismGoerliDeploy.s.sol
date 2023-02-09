// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {Settings} from "src/Settings.sol";

/// @title Script to deploy Kwenta's Smart Margin Account Factory
/// @author JaredBorders (jaredborders@pm.me)
/// @dev steps to deploy and verify: 
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/OptimismGoerliDeploy.s.sol:OptimismGoerliDeployScript --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast -vvvv`
contract OptimismGoerliDeployScript is Script {
    /// @notice Kwenta owned multisig addresses
    address private constant KWENTA_ADMIN_DAO_MULTI_SIG =
        0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885;
    address private constant KWENTA_TREASURY_MULTI_SIG =
        0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991;

    /// @notice Kwenta defined Smart Margin Account trading fees
    uint256 private constant TRADE_FEE = 1;
    uint256 private constant LIMIT_ORDER_FEE = 1;
    uint256 private constant STOP_ORDER_FEE = 1;

    /// @notice deploy Kwenta's Smart Margin Account Factory
    /// @dev settings, events, and account implementation are deployed
    /// @dev settings, events, and account implementation addresses 
    /// can be fetched from factory
    /// @return factory Kwenta's Smart Margin Account Factory
    function deploySmartMarginFactory() public returns (Factory factory) {
        // deploy Settings
        Settings settings = new Settings({
            _owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            _treasury: KWENTA_TREASURY_MULTI_SIG,
            _tradeFee: TRADE_FEE,
            _limitOrderFee: LIMIT_ORDER_FEE,
            _stopOrderFee: STOP_ORDER_FEE
        });
        // sanity check
        assert(address(settings) != address(0));

        // deploy Events
        Events events = new Events();
        // sanity check
        assert(address(events) != address(0));

        // deploy Account implementation
        Account implementation = new Account();
        // sanity check
        assert(address(implementation) != address(0));
        assert(implementation.owner() == address(0));

        // deploy Factory
        factory = new Factory({
            _owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            _settings: address(settings),
            _events: address(events),
            _implementation: address(implementation)
        });
        // sanity check
        assert(address(factory) != address(0));
    }
    
    /// @notice deploy Kwenta's Smart Margin Account Factory on Optimism Goerli
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deploySmartMarginFactory();

        vm.stopBroadcast();
    }
}
