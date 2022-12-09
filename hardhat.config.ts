import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-interact";

dotenv.config();

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
    },
    namedAccounts: {
        deployer: 0,
    },
    paths: {
        sources: "contracts",
        artifacts: "artifacts",
    },
    networks: {
        hardhat: {
            accounts: {
                count: 30,
                accountsBalance: "10000000000000000000000", // 10ETH (Default)
            },
        },
        localhost: {
            chainId: 31337,
        },
        "optimistic-goerli": {
            url: process.env.ARCHIVE_NODE_URL_GOERLI_L2
                ? process.env.ARCHIVE_NODE_URL_GOERLI_L2
                : "",
            accounts: process.env.DEPLOYER_PRIVATE_KEY
                ? [process.env.DEPLOYER_PRIVATE_KEY]
                : undefined,
            verify: {
                etherscan: {
                    apiUrl: "https://api-goerli-optimistic.etherscan.io",
                },
            },
        },
        "optimistic-mainnet": {
            url: process.env.ARCHIVE_NODE_URL_L2
                ? process.env.ARCHIVE_NODE_URL_L2
                : "",
            accounts: process.env.DEPLOYER_PRIVATE_KEY
                ? [process.env.DEPLOYER_PRIVATE_KEY]
                : undefined,
            verify: {
                etherscan: {
                    apiUrl: "https://api-optimistic.etherscan.io",
                },
            },
        },
    },
    gasReporter: {
        enabled: true,
        currency: "USD",
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
};

export default config;
