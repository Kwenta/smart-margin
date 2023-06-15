// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/*//////////////////////////////////////////////////////////////
                           FOR REFERENCE ONLY
    //////////////////////////////////////////////////////////////*/

// import "forge-std/Script.sol";
// import "forge-std/console2.sol";
// import "../../utils/parameters/OptimismGoerliParameters.sol";
// import "../../utils/parameters/OptimismParameters.sol";
// import {Account} from "src/Account.sol";
// import {Events} from "src/Events.sol";
// import {IAddressResolver} from "../../utils/interfaces/IAddressResolver.sol";
// import {Settings} from "src/Settings.sol";

// /// @title Script to upgrade the Account implementation to v2.0.1 AND deploy the Settings contract
// /// @author JaredBorders (jaredborders@pm.me)

// /// @dev steps to deploy and verify on Optimism:
// /// (1) load the variables in the .env file via `source .env`
// /// (2) run `forge script script/upgrades/v2.0.1/Upgrade.s.sol:UpgradeAccountOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
// /// (3) Smart Margin Account Factory owner (i.e. Kwenta multisig) will need to call `upgradeAccountImplementation` on the Factory
// ///     with the address of the new Account implementation
// contract UpgradeAccountOptimism is Script {
//     function run() public {
//         uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         upgrade();

//         vm.stopBroadcast();
//     }

//     function upgrade()
//         public
//         returns (address implementation, address settings, address events)
//     {
//         // resolve necessary addresses via the Synthetix Address Resolver
//         IAddressResolver addressResolver =
//             IAddressResolver(OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER);

//         // fetch sUSD proxy address via the Synthetix Address Resolver
//         address marginAsset =
//             addressResolver.getAddress({name: bytes32("ProxysUSD")});
//         assert(marginAsset != address(0));

//         // fetch FuturesMarketManager address via the Synthetix Address Resolver
//         address futuresMarketManager =
//             addressResolver.getAddress({name: bytes32("FuturesMarketManager")});
//         assert(futuresMarketManager != address(0));

//         // fetch SystemStatus address via the Synthetix Address Resolver
//         address systemStatus =
//             addressResolver.getAddress({name: bytes32("SystemStatus")});
//         assert(systemStatus != address(0));

//         // deploy settings
//         /// @dev owner on Optimism is the kwenta admin DAO multisig
//         settings = address(
//             new Settings({
//                 _owner: OPTIMISM_KWENTA_ADMIN_DAO_MULTI_SIG
//             })
//         );

//         console2.log("Settings Deployed:", settings);

//         // deploy events
//         events = address(new Events({_factory: OPTIMISM_FACTORY}));

//         console2.log("Events Deployed:", events);

//         // deploy v2.0.1
//         implementation = address(
//             new Account({
//                 _factory: OPTIMISM_FACTORY,
//                 _events: events,
//                 _marginAsset: marginAsset,
//                 _futuresMarketManager: futuresMarketManager,
//                 _systemStatus: systemStatus,
//                 _gelato: OPTIMISM_GELATO,
//                 _ops: OPTIMISM_OPS,
//                 _settings: settings
//             })
//         );

//         console2.log("Account Implementation v2.0.1 Deployed:", implementation);
//     }
// }

// /// @dev steps to deploy and verify on Optimism Goerli:
// /// (1) load the variables in the .env file via `source .env`
// /// (2) run `forge script script/upgrades/v2.0.1/Upgrade.s.sol:UpgradeAccountOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
// /// (3) Smart Margin Account Factory owner (i.e. Kwenta multisig) will need to call `upgradeAccountImplementation` on the Factory
// ///     with the address of the new Account implementation
// contract UpgradeAccountOptimismGoerli is Script {
//     function run() public {
//         uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         upgrade();

//         vm.stopBroadcast();
//     }

//     function upgrade()
//         public
//         returns (address implementation, address settings, address events)
//     {
//         // resolve necessary addresses via the Synthetix Address Resolver
//         IAddressResolver addressResolver =
//             IAddressResolver(OPTIMISM_GOERLI_SYNTHETIX_ADDRESS_RESOLVER);

//         // fetch sUSD proxy address via the Synthetix Address Resolver
//         address marginAsset =
//             addressResolver.getAddress({name: bytes32("ProxysUSD")});
//         assert(marginAsset != address(0));

//         // fetch FuturesMarketManager address via the Synthetix Address Resolver
//         address futuresMarketManager =
//             addressResolver.getAddress({name: bytes32("FuturesMarketManager")});
//         assert(futuresMarketManager != address(0));

//         // fetch SystemStatus address via the Synthetix Address Resolver
//         address systemStatus =
//             addressResolver.getAddress({name: bytes32("SystemStatus")});
//         assert(systemStatus != address(0));

//         // deploy settings
//         /// @dev owner on Optimism Goerli is the deployer address
//         settings = address(
//             new Settings({
//                 _owner: OPTIMISM_GOERLI_DEPLOYER
//             })
//         );

//         console2.log("Settings Deployed:", settings);

//         // deploy events
//         events = address(new Events({_factory: OPTIMISM_GOERLI_FACTORY}));

//         console2.log("Events Deployed:", events);

//         // deploy v2.0.1
//         implementation = address(
//             new Account({
//                 _factory: OPTIMISM_GOERLI_FACTORY,
//                 _events: events,
//                 _marginAsset: marginAsset,
//                 _futuresMarketManager: futuresMarketManager,
//                 _systemStatus: systemStatus,
//                 _gelato: OPTIMISM_GOERLI_GELATO,
//                 _ops: OPTIMISM_GOERLI_OPS,
//                 _settings: settings
//             })
//         );

//         console2.log("Account Implementation v2.0.1 Deployed:", implementation);
//     }
// }
