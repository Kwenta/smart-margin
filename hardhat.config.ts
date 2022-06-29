import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";
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
    networks: {
        optimistic_mainnet: {
            url:
                process.env.ARCHIVE_NODE_URL_L2 !== undefined
                    ? process.env.ARCHIVE_NODE_URL_L2
                    : "",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
            verify: {
                etherscan: {
                    apiUrl: "https://api-optimistic.etherscan.io",
                },
            },
        },
        optimistic_kovan: {
            url: "https://kovan.optimism.io",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
            blockGasLimit: 30_000_000,
            gas: 15_000_000,
            gasPrice: 1_000_000,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // here this will by default take the first account as deployer
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
