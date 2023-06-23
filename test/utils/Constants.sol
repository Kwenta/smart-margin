// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/*//////////////////////////////////////////////////////////////
                              TEST VALUES
    //////////////////////////////////////////////////////////////*/

// BLOCK_NUMBER corresponds to Optimism network
// state @ Jun-22-2023 05:00:19 PM +UTC
// hard coded addresses are only guaranteed for this block
// used to create a consistent and realistic test environment
// exposing Synthetix PerpsV2
uint256 constant BLOCK_NUMBER = 105_927_221;

// test deployer address with ETH
address constant DEPLOYER = 0x39CFcA7b389529ac861CbB05aDD802e5B06E5101;

// test user address w/ sUSD and ETH
address constant USER = 0x4aeB065bbD8E00e03BaF59097013a984aB74f456;

// test delegate address
address constant DELEGATE = address(0xDE1A6A7E);

// test amount used throughout tests
uint256 constant AMOUNT = 10_000 ether;

// test amount used for swaps
uint256 constant SWAP_AMOUNT = 100 ether;

// test margin delta used throughout tests
int256 constant MARGIN_DELTA = 1 ether;

// test size delta used throughout tests
int256 constant SIZE_DELTA = -1 ether;

// test target price used throughout tests
uint256 constant TARGET_PRICE = 9 ether;

// test fill price used throughout tests
uint256 constant FILL_PRICE = 10 ether;

// test desiredFillPrice used throughout tests
uint128 constant DESIRED_FILL_PRICE = 1 ether;

/*//////////////////////////////////////////////////////////////
                                 KWENTA
    //////////////////////////////////////////////////////////////*/

// kwenta treasury multisig
address constant KWENTA_TREASURY = 0x82d2242257115351899894eF384f779b5ba8c695;

// tracking code used when modifying positions
bytes32 constant TRACKING_CODE = "KWENTA";

// address used for testing the AccountProxy Beacon
address constant BEACON = address(0xBEAC0);

/*//////////////////////////////////////////////////////////////
                               SYNTHETIX
    //////////////////////////////////////////////////////////////*/

// Synthetix (ReadProxyAddressResolver)
address constant ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;

// Synthetix (ProxyERC20sUSD)
address constant MARGIN_ASSET = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;

// Synthetix contract names
bytes32 constant PROXY_SUSD = "ProxysUSD";
bytes32 constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";
bytes32 constant SYSTEM_STATUS = "SystemStatus";
bytes32 constant PERPS_V2_EXCHANGE_RATE = "PerpsV2ExchangeRate";

// Synthetix PerpsV2 market key(s)
bytes32 constant sETHPERP = "sETHPERP";
bytes32 constant sBTCPERP = "sBTCPERP";
bytes32 constant sAUDPERP = "sAUDPERP";

/*//////////////////////////////////////////////////////////////
                                 GELATO
    //////////////////////////////////////////////////////////////*/

// Gelato related addresses
address constant GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef;
address constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;
address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

// test fee Gelato will charge for filling conditional orders
uint256 constant GELATO_FEE = 69;

/*//////////////////////////////////////////////////////////////
                                UNISWAP
    //////////////////////////////////////////////////////////////*/

address constant UNISWAP_UNIVERSAL_ROUTER =
    0xb555edF5dcF85f42cEeF1f3630a52A108E55A654;

/*//////////////////////////////////////////////////////////////
                                  DAI
    //////////////////////////////////////////////////////////////*/

address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
address constant EOA_WITH_DAI = 0x99343B21B33243cE44acfad0a5620B758Ef8817a;

/*//////////////////////////////////////////////////////////////
                                  WETH
    //////////////////////////////////////////////////////////////*/

address constant WETH = 0x4200000000000000000000000000000000000006;
address constant EOA_WITH_WETH = 0x43CB54C706FaF6780dd89cc9186F8DABFAD1834c;
