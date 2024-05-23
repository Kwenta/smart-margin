// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @dev for Synthetix addresses see:
/// https://github.com/Synthetixio/synthetix-docs/blob/master/content/addresses.md#mainnet-optimism-l2

// v2.1.3 deployer
address constant OPTIMISM_DEPLOYER = 0x12d970154Ac171293323f20757130d5731850deB;

address constant OPTIMISM_PDAO = 0xe826d43961a87fBE71C91d9B73F7ef9b16721C07;

address constant OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER =
    0x1Cb059b7e74fD21665968C908806143E744D5F30;

address constant OPTIMISM_GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;

address constant OPTIMISM_OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;

// v2.1.4
address constant OPTIMISM_IMPLEMENTATION =
    0x0f716Fc517955863824CD9317603E4795EDfffb4;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_EVENTS = 0x6B32d15a6Cb77ea227A6Fb19532b2de542c45AC6;

// updated with v2.1.3 implementation
address constant OPTIMISM_FACTORY = 0x8234F990b149Ae59416dc260305E565e5DAfEb54;

// released with v2.1.4 implementation (used by v2.1.*)
address constant OPTIMISM_SETTINGS = 0xf36003a5dd0B17D51ca1525857dEf220E579447D;

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

/*//////////////////////////////////////////////////////////////
                        TOKEN WHITELIST
//////////////////////////////////////////////////////////////*/

// https://optimistic.etherscan.io/address/0x7F5c764cBc14f9669B88837ca1490cCa17c31607#code
address constant OPTIMISM_USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

// https://optimistic.etherscan.io/address/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
address constant OPTIMISM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

// https://optimistic.etherscan.io/address/0x94b008aA00579c1307B0EF2c499aD98a8ce58e58
address constant OPTIMISM_USDT = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;

// https://optimistic.etherscan.io/address/0xc40F949F8a4e094D1b49a23ea9241D289B7b2819
address constant OPTIMISM_LUSD = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
