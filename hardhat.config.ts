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
                version: "0.8.13",
            },
            {
                version: "0.5.16",
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
        localhost: {
            chainId: 31337,
        },
        "optimistic-kovan": {
            url: process.env.ARCHIVE_NODE_URL_KOVAN_L2
                ? process.env.ARCHIVE_NODE_URL_KOVAN_L2
                : "",
            accounts: process.env.DEPLOYER_PRIVATE_KEY
                ? [process.env.DEPLOYER_PRIVATE_KEY]
                : undefined,
            verify: {
                etherscan: {
                    apiUrl: "https://api-kovan-optimistic.etherscan.io",
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
