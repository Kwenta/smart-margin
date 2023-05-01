# Kwenta Smart Margin

[![Github Actions][gha-badge]][gha]
[![Foundry][foundry-badge]][foundry]
[![License: MIT][license-badge]][license]

[gha]: https://github.com/Kwenta/margin-manager/actions
[gha-badge]: https://github.com/Kwenta/margin-manager/actions/workflows/test.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## High-Level Overview

Contracts to manage account abstractions and features on top of [Synthetix Perps V2](https://github.com/Synthetixio/synthetix/blob/develop/contracts/PerpsV2Market.sol).

### System Diagram

<p align="center">
  <img src="/diagrams/Abstract-System-Diagram.png" width="1000" height="600" alt="System-Diagram"/>
</p>

## Contracts Overview

> See ./deploy-addresses/ for deployed contract addresses

The Margin Manager codebase consists of the `Factory` and `Account` contracts, and all of the associated dependencies. The purpose of the `Factory` is to create/deploy trading accounts (`Account` contracts) for users that support features ranging from cross-margin, conditional orders, copy trading, etc.. Once a smart margin account has been created, the main point of entry is the `Account.execute` function. `Account.execute` allows users to execute a set of commands describing the actions/trades they want executed by their account.

### User Entry: MarginBase Command Execution

Calls to `Account.execute`, the entrypoint to the smart margin account, require 2 main parameters:

`IAccount.Command commands`: An array of `enum`. Each enum represents 1 command that the transaction will execute.
`bytes[] inputs`: An array of `bytes` strings. Each element in the array is the encoded parameters for a command.

`commands[i]` is the command that will use `inputs[i]` as its encoded input parameters.

The supported commands can be found below (ordering may _not_ match what is defined in `IAccount.sol`):

```
ACCOUNT_MODIFY_MARGIN
ACCOUNT_WITHDRAW_ETH
PERPS_V2_MODIFY_MARGIN
PERPS_V2_WITHDRAW_ALL_MARGIN
PERPS_V2_SUBMIT_ATOMIC_ORDER
PERPS_V2_SUBMIT_DELAYED_ORDER
PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
PERPS_V2_CLOSE_POSITION
PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER
PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER
PERPS_V2_CANCEL_DELAYED_ORDER
PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
GELATO_PLACE_CONDITIONAL_ORDER
GELATO_CANCEL_CONDITIONAL_ORDER
```

#### How the input bytes are structured

Each input bytes string is merely the abi encoding of a set of parameters. Depending on the command chosen, the input bytes string will be different. For example:

The inputs for `PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER` is the encoding of 3 parameters:

`address`: The Synthetix PerpsV2 Market address
`int256`: The size delta of the order to be submitted
`uint256`: The desired fill price of the order

Whereas in contrast `PERPS_V2_CANCEL_DELAYED_ORDER` has just 1 parameter encoded:

`address`: The Synthetix PerpsV2 Market address which has an active delayed order submitted by this account

Encoding parameters in a bytes string in this way gives us maximum flexiblity to be able to support many commands which require different datatypes in a gas-efficient way.

For a more detailed breakdown of which parameters you should provide for each command take a look at the `Account.dispatch` function.

Developer documentation to give a detailed explanation of the inputs for every command can be found in the [wiki](https://github.com/Kwenta/margin-manager/wiki/Commands)

#### Diagram

<p align="center">
  <img src="/diagrams/Execution-Flow.png" width="1000" height="600" alt="Execution-Flow"/>
</p>

#### Reference

The command execution design was inspired by Uniswap's [Universal Router](https://github.com/Uniswap/universal-router).

### Events

Certain actions performed by the smart margin account emit events (such as depositing margin, or placing a conditional order). These events can be used to track the state of the account and to monitor the account's activity. To avoid monitoring a large number of accounts for events, we consolidate all events into a single `Events' contract`. Smart margin accounts make external calls to the `Events` contract to emit events. This costs more gas, but significantly reduces the load on our event monitoring infrastructure.

### Orders

The term "order" is used often in this codebase. Smart margin accounts natively define conditional orders, which include limit orders, stop-loss orders, and redcue-only flavors of the former two. It also supports a variety of other Synthetix PerpsV2 orders which are explicity defined by `IAccount.Command commands`.

### Upgradability

Smart margin accounts are upgradable. This is achieved by using a proxy pattern, where the `Account` contract is the implementation and the `AccountProxy` contract is the proxy. The `AccountProxy` contract is the contract that is deployed by the `Factory` and is the contract that users interact with. The `AccountProxy` contract delegates all calls to the `Account` contract. The `Account` contract can be upgraded by the `Factory` contract due to the `Factory` acting as a Beacon contract for the proxy. See further details on Beacons [here](https://docs.openzeppelin.com/contracts/3.x/api/proxy#beacon). One important difference between the standard Beacon implementation and our own, is that the Beacon (i.e. the `Factory`) is _not_ upgradeable. This is to prevent the Beacon from being upgraded and the proxy implementation being changed to a malicious contract.

Finally, all associated functionality related to upgradability can be disabled by the `Factory` contract owner.

## Folder Structure
```
src
├── Account.sol
├── AccountProxy.sol
├── Events.sol
├── Factory.sol
├── Settings.sol
├── interfaces
│   ├── IAccount.sol
│   ├── IAccountProxy.sol
│   ├── IEvents.sol
│   ├── IFactory.sol
│   ├── IOps.sol
│   ├── ISettings.sol
│   └── synthetix
│       ├── IFuturesMarketManager.sol
│       ├── IPerpsV2MarketConsolidated.sol
│       └── ISystemStatus.sol
└── utils
    ├── Auth.sol
    └── OpsReady.sol
```

## Test Coverage

| File                           | % Lines          | % Statements     | % Branches      | % Funcs         |
|--------------------------------|------------------|------------------|-----------------|-----------------|
| src/Account.sol                | 98.53% (201/204) | 98.61% (213/216) | 92.11% (70/76)  | 100.00% (35/35) |
| src/AccountProxy.sol           | 100.00% (10/10)  | 76.92% (10/13)   | 50.00% (3/6)    | 100.00% (6/6)   |
| src/Events.sol                 | 100.00% (6/6)    | 100.00% (6/6)    | 100.00% (0/0)   | 100.00% (6/6)   |
| src/Factory.sol                | 100.00% (27/27)  | 100.00% (34/34)  | 85.71% (12/14)  | 100.00% (6/6)   |
| src/Settings.sol               | 100.00% (2/2)    | 100.00% (2/2)    | 100.00% (0/0)   | 100.00% (1/1)   |
| src/utils/Auth.sol             | 100.00% (15/15)  | 100.00% (18/18)  | 100.00% (10/10) | 100.00% (5/5)   |
| src/utils/OpsReady.sol         | 100.00% (3/3)    | 100.00% (4/4)    | 75.00% (3/4)    | 100.00% (1/1)   |

## Usage

### Setup

1. Make sure to create an `.env` file following the example given in `.env.example`

2. Install [Slither](https://github.com/crytic/slither#how-to-install)

### Tests

#### Running Tests

1. Follow the [Foundry guide to working on an existing project](https://book.getfoundry.sh/projects/working-on-an-existing-project.html)

2. Build project

```
npm run compile
```

3. Execute both unit and integration tests (both run in forked environments)

```
npm run test
```

4. Run specific test

```
forge test --fork-url $(grep ARCHIVE_NODE_URL_GOERLI_L2 .env | cut -d '=' -f2) --match-test TEST_NAME -vvv
```

> tests will fail if you have not set up your .env (see .env.example)

### Upgradability

> Upgrades can be dangerous. Please ensure you have a good understanding of the implications of upgrading your contracts before proceeding. Storage collisions, Function signature collisions, and other issues can occur.

#### Update Account Implementation

> note that updates to `Account` are reflected in all smart margin accounts, regardless of whether they were created before or after the `Account` upgrade.

1. Create new version of `Account.sol` (ex: `AccountV2.sol`)
2. Run slither analysis to ensure no storage collisions with previous version

```
slither-check-upgradeability . Account --new-contract-name AccountV2 --proxy-name AccountProxy
```

3. Reference `./script` directory and `Upgrade.s.sol`
4. Ensure that the `Events` contract address is set correctly in the `Factory` contract 
5. Ensure that the `Events` contract is compatible with the new `Account` contract

## Project Tools

### Static Analysis

1. [Slither](https://github.com/crytic/slither)

```
npm run analysis:slither
```

2. [Solsat](https://github.com/0xKitsune/solstat)

```
npm run analysis:solsat
```

### Formatting

1. Project uses Foundry's formatter:

```
npm run format
```

### Code Coverage

1. Project uses Foundry's code coverage tool:

```
npm run coverage
```

### Gas Snapshot
> Snapshots should be updated after every contract change

1. Project uses Foundry's gas snapshot tool:

```
npm run gas-snapshot
```

2. To view the gas snapshot, navigate to `./gas-snapshot`
