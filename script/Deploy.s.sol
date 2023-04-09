// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";

interface IAddressResolver {
    function getAddress(bytes32 name) external view returns (address);
}

/// @title Script to deploy Kwenta's Smart Margin Account Factory
/// @author JaredBorders (jaredborders@pm.me)
contract Setup {
    function deploySystem(
        address _owner,
        address _addressResolver,
        address _gelato,
        address _ops
    ) public returns (Factory factory, Events events, Account implementation) {
        // deploy the factory, setting owner as the deployer's address
        factory = deploySmartMarginFactory({_owner: address(this)});

        // deploy the events contract and set the factory
        events = deployEvents({_factory: address(factory)});

        // resolve necessary addresses via the Synthetix Address Resolver
        address marginAsset = IAddressResolver(_addressResolver).getAddress({
            name: bytes32("ProxysUSD")
        });
        address futuresMarketManager = IAddressResolver(_addressResolver)
            .getAddress({name: bytes32("FuturesMarketManager")});
        address systemStatus = IAddressResolver(_addressResolver).getAddress({
            name: bytes32("SystemStatus")
        });

        // deploy the account implementation
        implementation = deployAccountImplementation({
            _events: address(events),
            _marginAsset: marginAsset,
            _futuresMarketManager: futuresMarketManager,
            _systemStatus: systemStatus,
            _gelato: _gelato,
            _ops: _ops
        });

        // update the factory with the new account implementation
        factory.upgradeAccountImplementation({
            _implementation: address(implementation)
        });

        // transfer ownership of the factory to the owner
        factory.transferOwnership({newOwner: _owner});
    }

    function deploySmartMarginFactory(address _owner)
        internal
        returns (Factory factory)
    {
        factory = new Factory({
            _owner: _owner
        });
    }

    function deployEvents(address _factory) internal returns (Events events) {
        events = new Events({
            _factory: _factory
        });
    }

    function deployAccountImplementation(
        address _events,
        address _marginAsset,
        address _futuresMarketManager,
        address _systemStatus,
        address _gelato,
        address _ops
    ) internal returns (Account implementation) {
        implementation = new Account({
            _events: _events,
            _marginAsset: _marginAsset,
            _futuresMarketManager: _futuresMarketManager,
            _systemStatus: _systemStatus,
            _gelato: _gelato,
            _ops: _ops
        });
    }
}

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
contract DeployOptimism is Script, Setup {
    address private constant KWENTA_ADMIN_DAO_MULTI_SIG =
        0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885;
    address private constant SYNTHETIX_ADDRESS_RESOLVER =
        0x1Cb059b7e74fD21665968C908806143E744D5F30;
    address private constant GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;
    address private constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySystem({
            _owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            _addressResolver: SYNTHETIX_ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });

        vm.stopBroadcast();
    }
}

/// @dev steps to deploy and verify on Optimism Goerli:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployOptimismGoerli --rpc-url $ARCHIVE_NODE_URL_GOERLI_L2 --broadcast --verify -vvvv`
/// @dev here the KWENTA_ADMIN_DAO_MULTI_SIG is the deployer address
contract DeployOptimismGoerli is Script, Setup {
    address private constant KWENTA_ADMIN_DAO_MULTI_SIG =
        0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;
    address private constant SYNTHETIX_ADDRESS_RESOLVER =
        0x9Fc84992dF5496797784374B810E04238728743d;
    address private constant GELATO = 0xF82D64357D9120a760e1E4C75f646C0618eFc2F3;
    address private constant OPS = 0x255F82563b5973264e89526345EcEa766DB3baB2;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Setup.deploySystem({
            _owner: KWENTA_ADMIN_DAO_MULTI_SIG,
            _addressResolver: SYNTHETIX_ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });

        vm.stopBroadcast();
    }
}
