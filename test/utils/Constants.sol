// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/*//////////////////////////////////////////////////////////////
                              TEST VALUES
//////////////////////////////////////////////////////////////*/

// BLOCK_NUMBER corresponds to Jan-04-2023 08:36:29 PM +UTC
// hard coded addresses are only guaranteed for this block
// used to create a consistent and realistic test environment exposing Synthetix PerpsV2
uint256 constant BLOCK_NUMBER = 60_242_268;

// test user address
address constant USER = 0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c;

// test smart margin account address (does not need to be a real account)
address constant ACCOUNT = address(0xBEEF);

// test amount used throughout tests
uint256 constant AMOUNT = 10_000 ether;

// max BPS; used for decimals calculations
uint256 constant MAX_BPS = 10_000;

// test margin delta used throughout tests
int256 constant MARGIN_DELTA = 1 ether;

// test size delta used throughout tests
int256 constant SIZE_DELTA = -1 ether;

// test target price used throughout tests
uint256 constant TARGET_PRICE = 9 ether;

// test fill price used throughout tests
uint256 constant FILL_PRICE = 10 ether;

// test price impact delta used throughout tests
uint128 constant PRICE_IMPACT_DELTA = 1 ether / 2;

/*//////////////////////////////////////////////////////////////
                                 KWENTA
//////////////////////////////////////////////////////////////*/

// kwenta treasury multisig
address constant KWENTA_TREASURY = 0x82d2242257115351899894eF384f779b5ba8c695;

// tracking code used when modifying positions
bytes32 constant TRACKING_CODE = "KWENTA";

// address used for testing the AccountProxy Beacon
address constant BEACON = address(0xA);

// settings fee values
uint256 constant TRADE_FEE = 1;
uint256 constant LIMIT_ORDER_FEE = 2;
uint256 constant STOP_ORDER_FEE = 3;

/*//////////////////////////////////////////////////////////////
                               SYNTHETIX
//////////////////////////////////////////////////////////////*/

// synthetix (ReadProxyAddressResolver)
address constant ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;

// synthetix (FuturesMarketManager)
address constant FUTURES_MARKET_MANAGER = 0xdb89f3fc45A707Dd49781495f77f8ae69bF5cA6e;

// Synthetix PerpsV2 market key(s)
bytes32 constant sETHPERP = "sETHPERP";
bytes32 constant sBTCPERP = "sBTCPERP";

/*//////////////////////////////////////////////////////////////
                                 GELATO
//////////////////////////////////////////////////////////////*/

// Gelato related addresses
address constant GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;
address constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;
address constant OPS_PROXY_FACTORY = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

// test fee Gelato will charge for filling conditional orders
uint256 constant GELATO_FEE = 69;
