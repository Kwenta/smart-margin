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
    0x85B466A1a6E2D2AcEf68Cb86BD3c6Efd7479E55d;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_SEPOLIA_EVENTS =
    0x3eF73cD1B3B708ab1F2ccB4AcDA036Ac3FDc3615;

// updated with v2.1.4 implementation
address constant OPTIMISM_SEPOLIA_FACTORY =
    0xF877315CfC91E69e7f4c308ec312cf91D66a095F;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_SEPOLIA_SETTINGS =
    0xA2dF816B2C5D8d799069d6a8a9f8464D402b5D25;

// uniswap v3:
// UniversalRouterV1_2
/// @custom:caution not official address
address constant OPTIMISM_SEPOLIA_UNISWAP_UNIVERSAL_ROUTER =
    0xD5bBa708b39537d33F2812E5Ea032622456F1A95;

// PERMIT2
/// @custom:caution assumes same address as on mainnet
address constant OPTIMISM_SEPOLIA_UNISWAP_PERMIT2 =
    0x000000000022D473030F116dDEE9F6B43aC78BA3;
