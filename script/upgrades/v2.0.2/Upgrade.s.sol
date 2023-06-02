// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../utils/parameters/OptimismGoerliParameters.sol";
import "../../utils/parameters/OptimismParameters.sol";
import {Account} from "src/Account.sol";
import {IAddressResolver} from "../../utils/interfaces/IAddressResolver.sol";

/// @title Script to upgrade the Account implementation v2.0.1 -> v2.0.1
/// @author JaredBorders (jaredborders@pm.me)

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/upgrades/v2.0.2/Upgrade.s.sol:UpgradeAccountOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
/// (3) Smart Margin Account Factory owner (i.e. Kwenta pDAO) will need to call `upgradeAccountImplementation` on the Factory with the address of the new Account implementation
contract UpgradeAccountOptimism is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        upgrade();

        vm.stopBroadcast();
    }

    function upgrade() public returns (address implementation) {
        IAddressResolver addressResolver =
            IAddressResolver(OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER);

        // deploy events
        events = address(new Events({_factory: OPTIMISM_FACTORY}));

        console2.log("Events Deployed:", events);

        implementation = address(
            new Account({
                _factory: OPTIMISM_FACTORY,
                _events: events,
                _marginAsset: addressResolver.getAddress({name: PROXY_SUSD}),
                _perpsV2ExchangeRate: addressResolver.getAddress({name: PERPS_V2_EXCHANGE_RATE}),
                _futuresMarketManager: addressResolver.getAddress({name: FUTURES_MARKET_MANAGER}),
                _systemStatus: addressResolver.getAddress({name: SYSTEM_STATUS}),
                _gelato: OPTIMISM_GELATO,
                _ops: OPTIMISM_OPS,
                _settings: OPTIMISM_SETTINGS
            })
        );

        console2.log("Account Implementation v2.0.2 Deployed:", implementation);
    }
}

/// @dev steps to deploy and verify on Optimism Goerli:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/upgrades/v2.0.2`/Upgrade.s.sol:UpgradeAccountOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
/// (3) Smart Margin Account Factory owner (i.e. Kwenta pDAO) will need to call `upgradeAccountImplementation` on the Factory with the address of the new Account implementation
contract UpgradeAccountOptimismGoerli is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        upgrade();

        vm.stopBroadcast();
    }

    function upgrade() public returns (address implementation) {
        IAddressResolver addressResolver =
            IAddressResolver(OPTIMISM_GOERLI_SYNTHETIX_ADDRESS_RESOLVER);

         // deploy events
        events = address(new Events({_factory: OPTIMISM_GOERLI_FACTORY}));

        console2.log("Events Deployed:", events);

        implementation = address(
            new Account({
                _factory: OPTIMISM_GOERLI_FACTORY,
                _events: OPTIMISM_GOERLI_EVENTS,
                _marginAsset: addressResolver.getAddress({name: PROXY_SUSD}),
                _perpsV2ExchangeRate: addressResolver.getAddress({name: PERPS_V2_EXCHANGE_RATE}),
                _futuresMarketManager: addressResolver.getAddress({name: FUTURES_MARKET_MANAGER}),
                _systemStatus: addressResolver.getAddress({name: SYSTEM_STATUS}),
                _gelato: OPTIMISM_GOERLI_GELATO,
                _ops: OPTIMISM_GOERLI_OPS,
                _settings: OPTIMISM_GOERLI_SETTINGS
            })
        );

        console2.log("Account Implementation v2.0.2 Deployed:", implementation);
    }
}
