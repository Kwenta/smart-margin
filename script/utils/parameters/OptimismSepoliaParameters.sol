// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @dev for Synthetix addresses see:
/// https://github.com/Synthetixio/synthetix-docs/blob/master/content/addresses.md#sepolia-optimism-l2

address constant OPTIMISM_SEPOLIA_DEPLOYER =
    0x12d970154Ac171293323f20757130d5731850deB;

address constant OPTIMISM_SEPOLIA_PDAO =
    0x12d970154Ac171293323f20757130d5731850deB;

address constant OPTIMISM_SEPOLIA_SYNTHETIX_ADDRESS_RESOLVER =
    0x352436A7d39F7250bfe2D3E1EC679A6e87c2F715;

// not deployed yet
address constant OPTIMISM_SEPOLIA_GELATO = address(0);

// not deployed yet
address constant OPTIMISM_SEPOLIA_OPS = address(0);

// v2.1.4
address constant OPTIMISM_SEPOLIA_IMPLEMENTATION =
    0x10B04483d762Bd4F193F35600112ad52391004A7;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_SEPOLIA_EVENTS =
    0x15725a8159629ca9763deC4211e309c94d9f5CB0;

// updated with v2.1.4 implementation
address constant OPTIMISM_SEPOLIA_FACTORY =
    0xF877315CfC91E69e7f4c308ec312cf91D66a095F;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_SEPOLIA_SETTINGS =
    0xb2a20fCdc506a685122847b21E34536359E94C56;

// uniswap v3:
// UniversalRouterV1_2
/// @custom:caution not official address
address constant OPTIMISM_SEPOLIA_UNISWAP_UNIVERSAL_ROUTER =
    0xD5bBa708b39537d33F2812E5Ea032622456F1A95;

// PERMIT2
/// @custom:caution assumes same address as on mainnet
address constant OPTIMISM_SEPOLIA_UNISWAP_PERMIT2 =
    0x000000000022D473030F116dDEE9F6B43aC78BA3;
