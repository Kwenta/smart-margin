# Kwenta Margin Manager

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

## Contract Overview

The Margin Manager codebase consists of the `MarginAccountFactory` and `MarginBase` contracts, and all of the associated dependencies. The purpose of the `MarginAccountFactory` is to create/deploy trading accounts (`MarginBase` contracts) for users that support features ranging from cross-margin, conditional orders, copy trading, etc..

### MarginBase Command Execution

Calls to `MarginBase.execute`, the entrypoint to the contracts, provide 2 main parameters:

`IMarginBaseTypes.Command commands`: An array of `enum`. Each enum represents 1 command that the transaction will execute.
`bytes[] inputs`: An array of `bytes` strings. Each element in the array is the encoded parameters for a command.

`commands[i]` is the command that will use `inputs[i]` as its encoded input parameters.

The supported commands can be found below:

```
PERPS_V2_MODIFY_MARGIN,
PERPS_V2_CLOSE_POSITION,
PERPS_V2_WITHDRAW_ALL_MARGIN,
PERPS_V2_SUBMIT_ATOMIC_ORDER,
PERPS_V2_SUBMIT_DELAYED_ORDER,
PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER,
PERPS_V2_CANCEL_DELAYED_ORDER,
PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
```

#### How the input bytes are structured

Each input bytes string is merely the abi encoding of a set of parameters. Depending on the command chosen, the input bytes string will be different. For example:

The inputs for `PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER` is the encoding of 3 parameters:

`address`: The Synthetix PerpsV2 Market address
`int256`: The size delta of the order to be submitted
`uint256`: The price impact delta of the order to be submitted

Whereas in contrast `PERPS_V2_CANCEL_DELAYED_ORDER` has just 1 parameter encoded:

`address`: The Synthetix PerpsV2 Market address which has an active delayed order submitted by this account

Encoding parameters in a bytes string in this way gives us maximum flexiblity to be able to support many commands which require different datatypes in a gas-efficient way.

For a more detailed breakdown of which parameters you should provide for each command take a look at the `MarginBase.dispatch` function.

Developer documentation to give a detailed explanation of the inputs for every command will be coming soon ✨!

#### Diagram

coming soon ✨

#### Reference

The command execution design was inspired by Uniswap's [Universal Router](https://github.com/Uniswap/universal-router).

## Folder Structure

    ├── ...
    ├── src                     # Source contracts
    ├── script                  # Foundry deployment scripts
    ├── test                    # Test files (alternatively `spec` or `tests`)
    │   ├── contracts           # Unit tests, fuzz tests using Foundry
    │   └── integration         # End-to-end, integration tests using Foundry
    └── ...

## Usage

### Setup

Make sure to create an `.env` file following the example given in `.env.example`

### Tests

#### Running Tests

1. Follow the [Foundry guide to working on an existing project](https://book.getfoundry.sh/projects/working-on-an-existing-project.html)

2. Build project
```
npm run compile
```

3. Execute unit tests
```
npm run unit-test
```

4. Execute integration tests
```
npm run integration-test
```
> integration tests will fail if you have not set up your .env (see .env.example)

### Deployment and Verification

coming soon ✨!