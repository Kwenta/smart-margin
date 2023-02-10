// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Script.sol";
// import {AccountV69} from "src/AccountV69.sol"; // (this is an example of the new Account implementation)

/// @title Script to upgrade the Account implementation
/// @author JaredBorders (jaredborders@pm.me)

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Upgrade.s.sol:UpgradeAccountOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast -vvvv`
/// (3) Smart Margin Account Factory owner (i.e. Kwenta multisig) will need to call `upgradeAccountImplementation` on the Factory
///     with the address of the new Account implementation
contract UpgradeAccountOptimism is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // AccountV69 newImplementation = new AccountV69();

        vm.stopBroadcast();
    }
}

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Upgrade.s.sol:UpgradeAccountOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast -vvvv`
/// (3) Smart Margin Account Factory owner (i.e. Kwenta multisig) will need to call `upgradeAccountImplementation` on the Factory
///     with the address of the new Account implementation
contract UpgradeAccountOptimismGoerli is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // AccountV69 newImplementation = new AccountV69();

        vm.stopBroadcast();
    }
}
