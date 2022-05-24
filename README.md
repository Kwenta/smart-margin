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

## Testing

### Running Foundry tests
1. Follow the [Foundry guide to working on an existing project](https://book.getfoundry.sh/projects/working-on-an-existing-project.html)

2. Build project
```
forge build
```
3. Execute tests
```
npm run foundry-test
```

### Running hardhat tests
1. Install all NPM packages
```
npm install
```
2. Build project
```
npx hardhat compile
```
3. Execute integration tests
```
npm run hh-test:integration
```
