// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/*//////////////////////////////////////////////////////////////
                              TEST VALUES
//////////////////////////////////////////////////////////////*/

// BLOCK_NUMBER corresponds to Optimism Goerli network state @ Apr-21-2023 08:49:56 PM +UTC
// hard coded addresses are only guaranteed for this block
// used to create a consistent and realistic test environment exposing Synthetix PerpsV2
uint256 constant BLOCK_NUMBER = 8_341_064;

// test deployer address with ETH
address constant DEPLOYER = 0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;

// test user address
address constant USER = 0x35eFbD8Ab6F7258C13D3ecDfc56c2c0DD094678F;

// test smart margin account address (does not need to be a real account)
address constant ACCOUNT = address(0xBEEF);

// test delegate address
address constant DELEGATE = address(0xBEEFBAE);

// test amount used throughout tests
uint256 constant AMOUNT = 10_000 ether;

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

// minimum ETH balance required to place a conditional order
uint256 constant MIN_ETH = 1 ether / 100;

/*//////////////////////////////////////////////////////////////
                                 KWENTA
//////////////////////////////////////////////////////////////*/

// kwenta treasury multisig
address constant KWENTA_TREASURY = 0xc625F59d51ecDff57FEFE535C80d318CA42A0Ec4;

// tracking code used when modifying positions
bytes32 constant TRACKING_CODE = "KWENTA";

// address used for testing the AccountProxy Beacon
address constant BEACON = address(0xA);

/*//////////////////////////////////////////////////////////////
                               SYNTHETIX
//////////////////////////////////////////////////////////////*/

// Synthetix (ReadProxyAddressResolver)
address constant ADDRESS_RESOLVER = 0x9Fc84992dF5496797784374B810E04238728743d;

// Synthetix (ProxyERC20sUSD)
address constant MARGIN_ASSET = 0xeBaEAAD9236615542844adC5c149F86C36aD1136;

// Synthetix contract names
bytes32 constant PROXY_SUSD = "ProxysUSD";
bytes32 constant FUTURES_MANAGER = "FuturesMarketManager";
bytes32 constant SYSTEM_STATUS = "SystemStatus";

// Synthetix PerpsV2 market key(s)
bytes32 constant sETHPERP = "sETHPERP";
bytes32 constant sBTCPERP = "sBTCPERP";
bytes32 constant sAUDPERP = "sAUDPERP";

/*//////////////////////////////////////////////////////////////
                                 GELATO
//////////////////////////////////////////////////////////////*/

// Gelato related addresses
address constant GELATO = 0xF82D64357D9120a760e1E4C75f646C0618eFc2F3;
address constant OPS = 0x255F82563b5973264e89526345EcEa766DB3baB2;
address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

// test fee Gelato will charge for filling conditional orders
uint256 constant GELATO_FEE = 69;
