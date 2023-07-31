// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @dev for Synthetix addresses see:
/// https://github.com/Synthetixio/synthetix-docs/blob/master/content/addresses.md#mainnet-optimism-l2

// v2.1.0 deployer
address constant OPTIMISM_DEPLOYER = 0xb7CefE980D41F2f83d4272526b0A0F04617da96b;

address constant OPTIMISM_PDAO = 0xe826d43961a87fBE71C91d9B73F7ef9b16721C07;

address constant OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER =
    0x1Cb059b7e74fD21665968C908806143E744D5F30;

address constant OPTIMISM_GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;

address constant OPTIMISM_OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;

// v2.0.2
address constant OPTIMISM_IMPLEMENTATION =
    0x3BC8D34314E77c2E36948Fd8F4B353f1baDc3F6C;

// released with v2.0.2 implementation
address constant OPTIMISM_EVENTS = 0x11193470df30B37Af9fc5Ec696c240D878bdfb42;

// updated with v2.0.2 implementation
address constant OPTIMISM_FACTORY = 0x8234F990b149Ae59416dc260305E565e5DAfEb54;

// released with v2.0.1 implementation
address constant OPTIMISM_SETTINGS = 0xD02813baF080d06FC6F706cF93F5DaA96D6edB17;

// key(s) used by Synthetix address resolver
bytes32 constant PROXY_SUSD = "ProxysUSD";
bytes32 constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";
bytes32 constant SYSTEM_STATUS = "SystemStatus";
bytes32 constant PERPS_V2_EXCHANGE_RATE = "PerpsV2ExchangeRate";

// uniswap
// UniversalRouterV1_2
address constant OPTIMISM_UNISWAP_UNIVERSAL_ROUTER =
    0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;

address constant OPTIMISM_UNISWAP_PERMIT2 =
    0x000000000022D473030F116dDEE9F6B43aC78BA3;
