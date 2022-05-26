/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { Contract } from "ethers";
import { mintToAccountSUSD } from "../utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";

dotenv.config();

// constants
const MINT_AMOUNT = ethers.BigNumber.from("100000000000000000000000"); // == $100_000 sUSD
const ACCOUNT_AMOUNT = ethers.BigNumber.from("10000000000000000000000"); // == $10_000 sUSD
const TEST_VALUE = ethers.BigNumber.from("1000000000000000000000"); // == $1_000 sUSD
const TREASURY_DAO = "0x82d2242257115351899894eF384f779b5ba8c695";

// synthetix
const ADDRESS_RESOLVER = "0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C";

// synthetix: proxy
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";
let sUSD: Contract;

// synthetix: market keys
// see: https://github.com/Synthetixio/synthetix/blob/develop/publish/deployed/mainnet-ovm/futures-markets.json
const MARKET_KEY_sETH = ethers.utils.formatBytes32String("sETH");
const MARKET_KEY_sBTC = ethers.utils.formatBytes32String("sBTC");
const MARKET_KEY_sLINK = ethers.utils.formatBytes32String("sLINK");
const MARKET_KEY_sUNI = ethers.utils.formatBytes32String("sUNI");

// cross margin
let marginAccountFactory: Contract;
let marginAccount: Contract;

// test accounts
let account0: SignerWithAddress;
let account1: SignerWithAddress;
let account2: SignerWithAddress;

const forkAtBlock = async (block: number) => {
    await network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: process.env.ARCHIVE_NODE_URL_L2,
                    blockNumber: block,
                },
            },
        ],
    });
};

describe("Integration: Test Cross Margin", () => {
    before("Fork and Mint sUSD to Test Account", async () => {
        forkAtBlock(9000000);

        [account0, account1, account2] = await ethers.getSigners();

        // mint account0 $1_000 sUSD
        await mintToAccountSUSD(account0.address, MINT_AMOUNT);

        const IERC20ABI = (
            await artifacts.readArtifact(
                "contracts/interfaces/IERC20.sol:IERC20"
            )
        ).abi;
        sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, ethers.provider);
        const balance = await sUSD.balanceOf(account0.address);
        expect(balance).to.equal(MINT_AMOUNT);
    });

    it("Should deploy MarginAccountFactory contract", async () => {
        marginAccountFactory = await (
            await ethers.getContractFactory("MarginAccountFactory")
        ).deploy("1.0.0", SUSD_PROXY, ADDRESS_RESOLVER);
        expect(marginAccountFactory.address).to.exist;
    });

    it("Should deploy a MarginBase contract and initialize it", async () => {
        const tx = await marginAccountFactory.connect(account0).newAccount();
        const rc = await tx.wait(); // 0ms, as tx is already confirmed
        const event = rc.events.find(
            (event: { event: string }) => event.event === "NewAccount"
        );
        const [owner, marginAccountAddress] = event.args;
        const MarginBaseABI = (
            await artifacts.readArtifact("contracts/MarginBase.sol:MarginBase")
        ).abi;
        marginAccount = new ethers.Contract(
            marginAccountAddress,
            MarginBaseABI,
            ethers.provider
        );
        expect(marginAccount.address).to.exist;

        // check sUSD is margin asset
        const marginAsset = await marginAccount.connect(account0).marginAsset();
        expect(marginAsset).to.equal(SUSD_PROXY);

        // check owner
        const actualOwner = await marginAccount.connect(account0).owner();
        expect(owner).to.equal(actualOwner);
        expect(actualOwner).to.equal(account0.address);
    });

    it("Test Opening Multiple Positions", async () => {
        // approve allowance for marginAccount to spend
        await sUSD
            .connect(account0)
            .approve(marginAccount.address, MINT_AMOUNT);

        // deposit (amount in wei == $10_000 sUSD) sUSD into margin account
        await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);

        //////////////// TRADES ////////////////

        // open ~ 1x LONG position in ETH-PERP Market
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            TEST_VALUE, // 1_000 sUSD
            ethers.BigNumber.from("500000000000000000"), // 0.5 ETH
            MARKET_KEY_sETH
        );

        // open 1x SHORT position in BTC-PERP Market
        // open 5x LONG position in LINK-PERP Market
        // open 5x SHORT position in UNI-PERP Market
    });

    it.skip("Test Modifying Multiple Positions", async () => {});

    it.skip("Test Position Rebalancing", async () => {});

    it.skip("Test Exiting Positions", async () => {});
});
