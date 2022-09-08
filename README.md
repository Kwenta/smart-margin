# Kwenta Margin Manager

Contracts to manage account abstractions and features on top of the Synthetix Futures Platform. This will support future implementations of cross margin, limit orders, stop orders (TBD), copy trading (TBD). 

The repo is a mix of [Hardhat](https://hardhat.org/) & [Foundry](https://github.com/foundry-rs/foundry). Hardhat will be used for integration testing and deployment. Foundry will be used for unit testing and fuzz testing. 

## Folder Structure

    ├── ...
    ├── contracts               # Source contracts
    ├── scripts                 # Hardhat deployment scripts
    ├── test                    # Test files (alternatively `spec` or `tests`)
    │   ├── contracts           # Unit tests, fuzz tests using Foundry
    │   └── integration         # End-to-end, integration tests using Hardhat
    └── ...

## Interacting

Make sure the deployer private key is set as an ENV if you want to use a signer
```
DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

### Using the CLI Interact Tool

To interact with the local deployment files (Factory, Settings)
```bash
npx hardhat interact --network <NETWORK_NAME>
# ie. npx hardhat interact --network optimistic-goerli  
```

To hot load a particular address (useful for attaching to a deployed margin account)
```bash
npx hardhat interact --network <NETWORK_NAME> <ADDRESS> <PATH_TO_ABI>
# npx hardhat interact --network optimistic-goerli 0xad1f15F747b1717D1Bf08e7E9a000B60D51344B9 ./artifacts/MarginBase.sol/MarginBase.json    
```

## Testing

### Running Unit Tests
1. Follow the [Foundry guide to working on an existing project](https://book.getfoundry.sh/projects/working-on-an-existing-project.html)

2. Build project
```
forge build
```
3. Execute unit tests
```
npm run f-test:unit
```

### Running Integration tests
1. Install all NPM packages
```
npm install
```
2. Build project
```
npx hardhat compile
```
3. Execute Hardhat integration tests
```
npm run hh-test:integration
```
4. Execute Foundry integration tests
```
npm run f-test:integration
```
