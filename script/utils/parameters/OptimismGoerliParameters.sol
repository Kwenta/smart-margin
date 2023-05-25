// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @dev for Synthetix addresses see:
/// https://github.com/Synthetixio/synthetix-docs/blob/master/content/addresses.md#goerli-optimism-l2

address constant OPTIMISM_GOERLI_DEPLOYER =
    0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;

address constant OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG =
    0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;

address constant OPTIMISM_GOERLI_SYNTHETIX_ADDRESS_RESOLVER =
    0x9Fc84992dF5496797784374B810E04238728743d;

address constant OPTIMISM_GOERLI_GELATO =
    0xF82D64357D9120a760e1E4C75f646C0618eFc2F3;

address constant OPTIMISM_GOERLI_OPS =
    0x255F82563b5973264e89526345EcEa766DB3baB2;

// v2.0.1
address constant OPTIMISM_GOERLI_IMPLEMENTATION =
    0x76210dbA7b06bC40ec4E152D2Dcfd6bFa8102a8a;

// released with v2.0.1 implementation
address constant OPTIMISM_GOERLI_EVENTS =
    0x91276Ad073Db556a84DA84aCFB960d3A2Fa7195a;

// updated with v2.0.1 implementation
address constant OPTIMISM_GOERLI_FACTORY =
    0x30582eeE34719fe22b1B6c3b607636A3ab94522E;

// released with v2.0.1 implementation
address constant OPTIMISM_GOERLI_SETTINGS =
    0xd2f3c4D549EF6AB572dB6512AB0e33f709E7caE1;

// key(s) used by Synthetix address resolver
bytes32 constant PROXY_SUSD = bytes32("ProxysUSD");
bytes32 constant FUTURES_MARKET_MANAGER = bytes32("FuturesMarketManager");
bytes32 constant SYSTEM_STATUS = bytes32("SystemStatus");
