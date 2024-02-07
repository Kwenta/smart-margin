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

address constant OPTIMISM_SEPOLIA_IMPLEMENTATION =
    0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6;

address constant OPTIMISM_SEPOLIA_EVENTS =
    0xd5fE5beAa04270B32f81Bf161768c44DF9880D11;

address constant OPTIMISM_SEPOLIA_FACTORY =
    0xF877315CfC91E69e7f4c308ec312cf91D66a095F;

address constant OPTIMISM_SEPOLIA_SETTINGS =
    0x33B725a1B2dE9178121D423D2A1c062C5452f310;

// uniswap v3:
// UniversalRouterV1_2
/// @custom:caution not official address
address constant OPTIMISM_SEPOLIA_UNISWAP_UNIVERSAL_ROUTER =
    0xD5bBa708b39537d33F2812E5Ea032622456F1A95;

// PERMIT2
/// @custom:caution assumes same address as on mainnet
address constant OPTIMISM_SEPOLIA_UNISWAP_PERMIT2 =
    0x000000000022D473030F116dDEE9F6B43aC78BA3;
