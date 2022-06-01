/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { Contract } from "ethers";
import { mintToAccountSUSD } from "../utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";

dotenv.config();

/**
 * README:
 * 
 * MarginBase offers true cross-margin for users via the MarginBase.distributeMargin()
 * function. distributeMargin() gives the caller the flexibility to distribute margin
 * equally across all positions after opening/closing/modifying any/some/all market positions.
 * More specifically, distributeMargin() takes an array of objects defined by the caller
 * which represent market positions the account will take.
 * 
 * example:
 * If Tom deposits 10_000 sUSD into a MarginBase account, and then passes this array of 
 * market positions to distributeMargin():
 * 
 * [{sETH, 1_000, 1*10e18}, {sUNI, 1_000, -900*10e18}]
 * 
 * Then he will have two active market positions: (1) 2x long in sETH and (2) 5x short in sUNI.
 * Notice he still has 8_000 sUSD of available margin which is not in either market. If
 * Tom wishes to use that margin, he can call distributeMargin() again with:
 * 
 * [{sETH, 4_000, 1*10e18}, {sUNI, 4_000, -900*10e18}]
 * 
 * That will increase the margin for each position, thus decreasing the leverage accordingly
 * (assuming that the size delta (1*10e18 or -900*10e18 in the above case) remains the same).
 * 
 * Furthermore, notice that once a position has been taken by the account, 
 * calling distributeMargin() with an array of market positions/orders that do no include the
 * currently active positions will work, as long as there is sufficient margin available for the 
 * position:
 * 
 * Assume Tom deposited 20_000 sUSD and made the same trades as above, he could then call
 * distributeMargin() with:
 * 
 * [{sBTC, 1_000, 0.5*10e18}]
 * 
 * He will now have three active market positions: (1)long in sETH (2) short in sUNI and (3) long in sBTC.
 * Notice, only 11_000 of his 20_000 margin is being used in markets, but that can be changed quite
 * easily.
 * 
 * The above examples will be followed below in the integration tests
 * 
 * Ultimately, the goal of MarginBase is to offer users the flexibility to define cross margin
 * however they see fit. Single positions with limited margin relative to account margin is supported
 * as well as equally distrubted margin among all active market positions. It is up to the caller/front-end
 * to implement whatever strategy that best serves them.
 * 
 * @author jaredborders
 */

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

    it("Should deploy MarginBase contract and initialize it", async () => {
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

    it.skip("Should Open Multiple Positions", async () => {
        // approve allowance for marginAccount to spend
        await sUSD
            .connect(account0)
            .approve(marginAccount.address, ACCOUNT_AMOUNT);

        // deposit (amount in wei == $10_000 sUSD) sUSD into margin account
        await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);

        //////////////// TRADES ////////////////

        // open ~1x LONG position in ETH-PERP Market
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            TEST_VALUE, // 1_000 sUSD
            ethers.BigNumber.from("500000000000000000"), // 0.5 ETH
            MARKET_KEY_sETH
        );

        // open ~1x SHORT position in BTC-PERP Market
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            TEST_VALUE, // 1_000 sUSD
            ethers.BigNumber.from("-30000000000000000"), // 0.03 BTC
            MARKET_KEY_sBTC
        );

        // open ~5x LONG position in LINK-PERP Market
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            TEST_VALUE, // 1_000 sUSD
            ethers.BigNumber.from("700000000000000000000"), // 700 LINK
            MARKET_KEY_sLINK
        );

        // open ~5x SHORT position in UNI-PERP Market
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            TEST_VALUE, // 1_000 sUSD
            ethers.BigNumber.from("-900000000000000000000"), // 900 UNI
            MARKET_KEY_sUNI
        );

        // check positions opened match what is seen on synthetix (margin, size, etc)
        // @TODO: perform checks
    });

    it.skip("Should Modify Multiple Positions", async () => {
        //////////////// TRADES ////////////////

        // modify ~1x LONG position in ETH-PERP Market to ~2x
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            0,
            ethers.BigNumber.from("1000000000000000000"), // 1 ETH
            MARKET_KEY_sETH
        );

        // modify ~1x SHORT position in BTC-PERP Market to ~2x
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            0,
            ethers.BigNumber.from("-60000000000000000"), // 0.06 BTC
            MARKET_KEY_sBTC
        );

        // modify ~5x LONG position in LINK-PERP Market to ~1x
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            0,
            ethers.BigNumber.from("140000000000000000000"), // 140 LINK
            MARKET_KEY_sLINK
        );

        // modify ~5x SHORT position in UNI-PERP Market to ~1x
        await marginAccount.connect(account0).depositAndModifyPositionForMarket(
            0,
            ethers.BigNumber.from("-180000000000000000000"), // 900 UNI
            MARKET_KEY_sUNI
        );

        // check positions match what is seen on synthetix (margin, size, etc)
        // @TODO: perform checks
    });

    it.skip("Test Position Rebalancing", async () => {});

    it.skip("Test Exiting Positions", async () => {});
});
