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
 * New Position Objects are defined as:
 * {
 *      Market Key, 
 *      Margin in sUSD (negative denotes withdraw from market), 
 *      Size of Position (negative denotes short position)
 * }
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
 * @TODO
 *
 * That will increase the margin for each position, thus decreasing the leverage accordingly
 * (assuming that the size delta (1*10e18 or -900*10e18 in the above case) remains the same).
 *
 * Furthermore, notice that once a position has been taken by the account,
 * calling distributeMargin() with an array of market positions/orders that do not include the
 * currently active positions will work, as long as there is sufficient margin available for the
 * positions specified:
 *
 * Assume Tom deposited 20_000 sUSD and made the same trades as above, he could then call
 * distributeMargin() with:
 *
 * [{sBTC, 1_000, 0.5*10e18}]
 *
 * He will now have three active market positions: (1) long in sETH (2) short in sUNI and (3) long in sBTC.
 * Notice, only 11_000 of his 20_000 margin is being used in markets, but that can be changed quite
 * easily.
 * 
 * Tom can also change the position sizes without altering the amount of margin in each 
 * active market position. He can do this by passing position objects with marginDelta set to "0"
 * and sizeDelta set to the newly desired size. An example of changing his above sETH long position
 * size and not altering his other positions:
 * 
 * [{sETH, 0, 5*10e18}]
 * 
 * His sETH is now 10x long position.
 *
 * Ultimately, the goal of MarginBase is to offer users the flexibility to define cross margin
 * however they see fit. Single positions with limited margin relative to account margin is supported
 * as well as equally distrubted margin among all active market positions. It is up to the caller/front-end
 * to implement whatever strategy that best serves them.
 * 
 * OPTHER NOTES
 * (1) Notice that there is an order fee taken when a futures position is opened
 *          which is relative to position size, thus deposited margin will not strictly 
 *          equal actual margin in market in the following tests. Expect difference 
 *          to be less than 1%.
 * 
 * (2) When closing a position, the margin will be transferred back to the 
 *          user's account, thus, that margin can be used in any subsequent
 *          new positions which may be opened/modified in the same transaction
 * ex: 
 * Assume a 1x BTC Long position already exists and then the following array of positions
 * is passed to distributeMargin:
 * 
 * [{sBTC, 0, -1*10e18}, {X}, {Y}, {Z}]
 * 
 * The first position object closes the BTC position, returning that margin to the account 
 * which can then be used to open or modify positions: X, Y, Z.
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

    it("Should Approve Allowance and Deposit Margin into Account", async () => {
        // approve allowance for marginAccount to spend
        await sUSD
            .connect(account0)
            .approve(marginAccount.address, ACCOUNT_AMOUNT);

        // confirm allowance
        const allowance = await sUSD.allowance(
            account0.address,
            marginAccount.address
        );
        expect(allowance).to.equal(ACCOUNT_AMOUNT);

        // deposit (amount in wei == $10_000 sUSD) sUSD into margin account
        await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);

        // confirm deposit
        const balance = await sUSD.balanceOf(marginAccount.address);
        expect(balance).to.equal(ACCOUNT_AMOUNT);
    });

    /**
     * For the following tests, the approximated leverage (1x, 3x, 5x, etc)
     * is not crucial. I added the approximations just for clarity. The
     * token prices at this current block (9000000) I only estimated.
     *
     * What is important are the multiples which change when new or modified
     * positions are passed to the contract (i.e. did size/margin/etc change appropriately)
     * */

    it("Should Open Single Position", async () => {
        // define new positions
        const newPositions = [
            {
                // open ~1x LONG position in ETH-PERP Market
                marketKey: MARKET_KEY_sETH,
                marginDelta: TEST_VALUE, // 1_000 sUSD
                sizeDelta: ethers.BigNumber.from("500000000000000000"),
            },
        ];

        // confirm number of open positions that were defined above
        await marginAccount.connect(account0).distributeMargin(newPositions);
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(1);

        // confirm correct position details: Market, Margin, Size
        // ETH
        const position = await marginAccount.connect(account0).activeMarketPositions(MARKET_KEY_sETH);
        expect(position.marketKey).to.equal(MARKET_KEY_sETH);
        expect(position.margin).to.be.closeTo(TEST_VALUE, TEST_VALUE.mul(1).div(100));
        expect(position.size).to.equal(ethers.BigNumber.from("500000000000000000"));
    });

    it("Should Open Multiple Positions", async () => {
        // define new positions
        const newPositions = [
            {
                // open ~1x SHORT position in BTC-PERP Market
                marketKey: MARKET_KEY_sBTC,
                marginDelta: TEST_VALUE, // 1_000 sUSD
                sizeDelta: ethers.BigNumber.from("-30000000000000000"), // 0.03 BTC
            },
            {
                // open ~5x LONG position in LINK-PERP Market
                marketKey: MARKET_KEY_sLINK,
                marginDelta: TEST_VALUE, // 1_000 sUSD
                sizeDelta: ethers.BigNumber.from("700000000000000000000"), // 700 LINK
            },
            {
                // open ~5x SHORT position in UNI-PERP Market
                marketKey: MARKET_KEY_sUNI,
                marginDelta: TEST_VALUE, // 1_000 sUSD
                sizeDelta: ethers.BigNumber.from("-900000000000000000000"), // 900 UNI
            },
        ];

        // confirm number of open positions
        await marginAccount.connect(account0).distributeMargin(newPositions);
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);

        // confirm correct position details: Market, Margin, Size
        // BTC
        const BTCposition = await marginAccount.connect(account0).activeMarketPositions(MARKET_KEY_sBTC);
        expect(BTCposition.marketKey).to.equal(MARKET_KEY_sBTC);
        expect(BTCposition.margin).to.be.closeTo(TEST_VALUE, TEST_VALUE.mul(1).div(100)); // 1% fee
        expect(BTCposition.size).to.equal(ethers.BigNumber.from("-30000000000000000")); // 0.03 BTC
        // LINK
        const LINKposition = await marginAccount.connect(account0).activeMarketPositions(MARKET_KEY_sLINK);
        expect(LINKposition.marketKey).to.equal(MARKET_KEY_sLINK);
        expect(LINKposition.margin).to.be.closeTo(TEST_VALUE, TEST_VALUE.mul(2).div(100)); // 2% fee
        expect(LINKposition.size).to.equal(ethers.BigNumber.from("700000000000000000000")); // 700 LINK
        // UNI
        const UNIposition = await marginAccount.connect(account0).activeMarketPositions(MARKET_KEY_sUNI);
        expect(UNIposition.marketKey).to.equal(MARKET_KEY_sUNI);
        expect(UNIposition.margin).to.be.closeTo(TEST_VALUE, TEST_VALUE.mul(2).div(100)); // 2% fee
        expect(UNIposition.size).to.equal(ethers.BigNumber.from("-900000000000000000000")); // 900 UNI
    });

    it.skip("Should Modify Multiple Position's Delta Size", async () => {
        /**
         * Notice that marginDelta for all positions is 0.
         * No withdrawing nor depositing into market positions, only
         * modifying position size (i.e. leverage)
         */

        //////////////// TRADES ////////////////

        const newPositions = [
            {
                // modify ~1x LONG position in ETH-PERP Market to ~3x
                marketKey: MARKET_KEY_sETH,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("1000000000000000000"), // 0.5 ETH -> 1.5 ETH
            },
            {
                // modify ~1x SHORT position in BTC-PERP Market to ~3x
                marketKey: MARKET_KEY_sBTC,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-60000000000000000"), // 0.03 BTC -> 0.09 BTC
            },
            {
                // modify ~5x LONG position in LINK-PERP Market to ~1x
                marketKey: MARKET_KEY_sLINK,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-560000000000000000000"), // 700 LINK -> 140 LINK
            },
            {
                // modify ~5x SHORT position in UNI-PERP Market to ~1x
                marketKey: MARKET_KEY_sUNI,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("720000000000000000000"), // 900 UNI -> 180 UNI
            },
        ];

        // confirm number of open positions
        await marginAccount.connect(account0).distributeMargin(newPositions);
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);
    });

    it.skip("Should Modify Multiple Position's Margin", async () => {
        /**
         * @TODO doc
         */

        //////////////// TRADES ////////////////

        const newPositions = [
            {
                // modify ~1x LONG position in ETH-PERP Market to ~3x
                marketKey: MARKET_KEY_sETH,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("1000000000000000000"), // 0.5 ETH -> 1.5 ETH
            },
            {
                // modify ~1x SHORT position in BTC-PERP Market to ~3x
                marketKey: MARKET_KEY_sBTC,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-60000000000000000"), // 0.03 BTC -> 0.09 BTC
            },
            {
                // modify ~5x LONG position in LINK-PERP Market to ~1x
                marketKey: MARKET_KEY_sLINK,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-560000000000000000000"), // 700 LINK -> 140 LINK
            },
            {
                // modify ~5x SHORT position in UNI-PERP Market to ~1x
                marketKey: MARKET_KEY_sUNI,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("720000000000000000000"), // 900 UNI -> 180 UNI
            },
        ];

        // confirm number of open positions
        await marginAccount.connect(account0).distributeMargin(newPositions);
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);
    });

    it.skip("Test Position Rebalancing", async () => {});

    it.skip("Test Exiting Positions", async () => {});
});
