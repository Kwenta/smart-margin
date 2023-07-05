// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "lib/forge-std/src/Script.sol";

import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {IAddressResolver} from "script/utils/interfaces/IAddressResolver.sol";
import {Settings} from "src/Settings.sol";

import {
    OPTIMISM_DEPLOYER,
    OPTIMISM_KWENTA_ADMIN_DAO_MULTI_SIG,
    OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER,
    OPTIMISM_GELATO,
    OPTIMISM_OPS,
    OPTIMISM_UNISWAP_UNIVERSAL_ROUTER,
    OPTIMISM_UNISWAP_PERMIT2,
    PROXY_SUSD,
    PERPS_V2_EXCHANGE_RATE,
    FUTURES_MARKET_MANAGER,
    SYSTEM_STATUS
} from "script/utils/parameters/OptimismParameters.sol";
import {
    OPTIMISM_GOERLI_DEPLOYER,
    OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG,
    OPTIMISM_GOERLI_SYNTHETIX_ADDRESS_RESOLVER,
    OPTIMISM_GOERLI_GELATO,
    OPTIMISM_GOERLI_OPS,
    OPTIMISM_GOERLI_UNISWAP_UNIVERSAL_ROUTER,
    OPTIMISM_GOERLI_UNISWAP_PERMIT2
} from "script/utils/parameters/OptimismGoerliParameters.sol";

/// @title Script to deploy Kwenta's Smart Margin Account Factory
/// @author JaredBorders (jaredborders@pm.me)
contract Setup {
    function deploySystem(
        address _deployer,
        address _owner,
        address _addressResolver,
        address _gelato,
        address _ops,
        address _universalRouter,
        address _permit2
    )
        public
        returns (
            Factory factory,
            Events events,
            Settings settings,
            Account implementation
        )
    {
        IAddressResolver addressResolver;

        {
            // define *initial* factory owner
            address temporaryOwner =
                _deployer == address(0) ? address(this) : _deployer;

            // deploy the factory
            factory = new Factory({
                _owner: temporaryOwner
            });

            // deploy the events contract and set the factory
            events = new Events({
                _factory: address(factory)
            });

            // deploy the settings contract
            settings = new Settings({
                _owner: _owner
            });

            // resolve necessary addresses via the Synthetix Address Resolver
            addressResolver = IAddressResolver(_addressResolver);
        }

        implementation = new Account({
            _factory: address(factory),
            _events: address(events),
            _marginAsset: addressResolver.getAddress({name: PROXY_SUSD}),
            _perpsV2ExchangeRate: addressResolver.getAddress({name: PERPS_V2_EXCHANGE_RATE}),
            _futuresMarketManager: addressResolver.getAddress({name: FUTURES_MARKET_MANAGER}),
            _systemStatus: addressResolver.getAddress({name: SYSTEM_STATUS}),
            _gelato: _gelato,
            _ops: _ops,
            _settings: address(settings),
            _universalRouter: _universalRouter,
            _permit2: _permit2
        });

        // update the factory with the new account implementation
        factory.upgradeAccountImplementation({
            _implementation: address(implementation)
        });

        // transfer ownership of the factory to the owner
        factory.transferOwnership({newOwner: _owner});
    }
}

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
contract DeployOptimism is Script, Setup {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySystem({
            _deployer: OPTIMISM_DEPLOYER,
            _owner: OPTIMISM_KWENTA_ADMIN_DAO_MULTI_SIG,
            _addressResolver: OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER,
            _gelato: OPTIMISM_GELATO,
            _ops: OPTIMISM_OPS,
            _universalRouter: OPTIMISM_UNISWAP_UNIVERSAL_ROUTER,
            _permit2: OPTIMISM_UNISWAP_PERMIT2
        });

        vm.stopBroadcast();
    }
}

/// @dev steps to deploy and verify on Optimism Goerli:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
contract DeployOptimismGoerli is Script, Setup {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySystem({
            _deployer: OPTIMISM_GOERLI_DEPLOYER,
            _owner: OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG,
            _addressResolver: OPTIMISM_GOERLI_SYNTHETIX_ADDRESS_RESOLVER,
            _gelato: OPTIMISM_GOERLI_GELATO,
            _ops: OPTIMISM_GOERLI_OPS,
            _universalRouter: OPTIMISM_GOERLI_UNISWAP_UNIVERSAL_ROUTER,
            _permit2: OPTIMISM_GOERLI_UNISWAP_PERMIT2
        });

        vm.stopBroadcast();
    }
}
