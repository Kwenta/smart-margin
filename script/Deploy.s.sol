// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {Settings} from "src/Settings.sol";

/// @title Script to deploy Kwenta's Smart Margin Account Factory
/// @author JaredBorders (jaredborders@pm.me)
contract Setup {
    function deploySmartMarginFactory(
        address owner,
        address treasury,
        uint256 tradeFee,
        uint256 limitOrderFee,
        uint256 stopOrderFee
    ) public returns (Factory factory) {
        Settings settings = new Settings({
            _owner: owner,
            _treasury: treasury,
            _tradeFee: tradeFee,
            _limitOrderFee: limitOrderFee,
            _stopOrderFee: stopOrderFee
        });

        Events events = new Events();

        Account implementation = new Account();

        // deploy Factory
        factory = new Factory({
            _owner: owner,
            _settings: address(settings),
            _events: address(events),
            _implementation: address(implementation)
        });
    }
}

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast -vvvv`
contract DeployOptimism is Script, Setup {
    address private constant KWENTA_ADMIN_DAO_MULTI_SIG =
        0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885;
    address private constant KWENTA_TREASURY_MULTI_SIG =
        0x82d2242257115351899894eF384f779b5ba8c695;

    uint256 private constant SETTINGS_TRADE_FEE = 1;
    uint256 private constant SETTINGS_LIMIT_ORDER_FEE = 1;
    uint256 private constant SETTINGS_STOP_ORDER_FEE = 1;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySmartMarginFactory({
            owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            treasury: KWENTA_TREASURY_MULTI_SIG,
            tradeFee: SETTINGS_TRADE_FEE,
            limitOrderFee: SETTINGS_LIMIT_ORDER_FEE,
            stopOrderFee: SETTINGS_STOP_ORDER_FEE
        });

        vm.stopBroadcast();
    }
}

/// @dev steps to deploy and verify on Optimism Goerli:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast -vvvv`
contract DeployOptimismGoerli is Script, Setup {
    address private constant KWENTA_ADMIN_DAO_MULTI_SIG = 0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;
    address private constant KWENTA_TREASURY_MULTI_SIG = 0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;

    uint256 private constant SETTINGS_TRADE_FEE = 1;
    uint256 private constant SETTINGS_LIMIT_ORDER_FEE = 1;
    uint256 private constant SETTINGS_STOP_ORDER_FEE = 1;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySmartMarginFactory({
            owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            treasury: KWENTA_TREASURY_MULTI_SIG,
            tradeFee: SETTINGS_TRADE_FEE,
            limitOrderFee: SETTINGS_LIMIT_ORDER_FEE,
            stopOrderFee: SETTINGS_STOP_ORDER_FEE
        });

        vm.stopBroadcast();
    }
}


/**

STEPS:

1) Add private key to .env file
2) check OP Goerli addresses (multisig and treasury)
3) Deploy to OP Goerli following above steps
4) Update addresses (Account, Events, Factory, Settings) in deploy-addresses/optimism-goerli.json
5) check OP addresses (multisig and treasury)
6) Deploy to OP following above steps
7) Update addresses (Account, Events, Factory, Settings) in deploy-addresses/optimism.json
8) update README to point readers to directory with deployed addresses
9) add broadcast info (abi, etc) to a new directory in deploy-addresses?
10) delete this comment (:

*/