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

// Synthetix (IPerpsV2DynamicFeesModule)
address constant PERPS_V2_DYNAMIC_FEES_MODULE = 0x05F6f46e5EED6dec1D8Cc3c6e8169D447966844d;

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
    0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
address constant UNISWAP_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

// fee tiers
// see: https://docs.uniswap.org/sdk/v3/reference/enums/FeeAmount
bytes3 constant HIGH_FEE_TIER = bytes3(uint24(10_000));
bytes3 constant MEDIUM_FEE_TIER = bytes3(uint24(3000));
bytes3 constant LOW_FEE_TIER = bytes3(uint24(500));
bytes3 constant LOWEST_FEE_TIER = bytes3(uint24(100));

/// @dev The length of the bytes encoded address
uint256 constant ADDR_SIZE = 20;

/// @dev The length of the bytes encoded fee
uint256 constant V3_FEE_SIZE = 3;

/// @dev The offset of a single token address (20) and pool fee (3)
uint256 constant NEXT_V3_POOL_OFFSET = ADDR_SIZE + V3_FEE_SIZE;

/// @dev The offset of an encoded pool key
/// Token (20) + Fee (3) + Token (20) = 43
uint256 constant V3_POP_OFFSET = NEXT_V3_POOL_OFFSET + ADDR_SIZE;

/// @dev The minimum length of an encoding that contains 2 or more pools
uint256 constant MULTIPLE_V3_POOLS_MIN_LENGTH =
    V3_POP_OFFSET + NEXT_V3_POOL_OFFSET;

/*//////////////////////////////////////////////////////////////
                                  DAI
//////////////////////////////////////////////////////////////*/

address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
address constant EOA_WITH_DAI = 0x99343B21B33243cE44acfad0a5620B758Ef8817a;

/*//////////////////////////////////////////////////////////////
                                  USDC
//////////////////////////////////////////////////////////////*/

address constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
