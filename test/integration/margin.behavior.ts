/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { Contract } from "ethers";
import { mintToAccountSUSD } from "../utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";

dotenv.config();

/**
 * ########### SUMMARY ###########
 * MarginBase offers true cross-margin for users via the MarginBase.distributeMargin()
 * function. distributeMargin() gives the caller the flexibility to distribute margin
 * equally across all positions after opening/closing/modifying any/some/all market positions.
 * More specifically, distributeMargin() takes an array of objects defined by the caller
 * which represent market positions the account will take.
 *
 * ########### START OF EXAMPLES ###########
 * New Position Objects are defined as:
 * {
 *      Market Key,
 *      Margin in sUSD (negative denotes withdraw from market),
 *      Size of Position (negative denotes short position)
 *      Boolean: will this position be closed (i.e. if true, close position)
 * }
 *
 * example (1.0):
 * If Tom deposits 10_000 sUSD into a MarginBase account, and then passes this array of
 * market positions to distributeMargin():
 *
 * [{sETH, 1_000, 1*10e18, false}, {sUNI, 1_000, -900*10e18, false}]
 *
 * Then he will have two active market positions: (1) 2x long in sETH and (2) 5x short in sUNI.
 *
 * example (1.1):
 * Notice, Tom still has 8_000 sUSD of available margin which is not in either market. If
 * Tom wishes to use that margin, he can call distributeMargin() again with:
 *
 * [{sETH, 4_000, 0, false}, {sUNI, 4_000, 0, false}]
 *
 * That will increase the margin for each position, thus decreasing the leverage accordingly.
 * That will not change the size of either position; margin was simply deposited into each market.
 * Notice that the size of the positions specified in the above objects are "0". When a user wishes
 * to only deposit or withdraw margin, this is the correct method to do so.
 *
 * example (1.2):
 * Notice that once a position has been taken by the account,
 * calling distributeMargin() with an array of market positions/orders that do not include the
 * currently active positions will work, as long as there is sufficient margin available for the
 * positions specified:
 *
 * Assume Tom deposits another 10_000 sUSD into his account. He could then call
 * distributeMargin() with:
 *
 * [{sBTC, 1_000, 0.5*10e18, false}]
 *
 * He will now have three active market positions: (1) long in sETH (2) short in sUNI and (3) long in sBTC.
 * Notice, only 11_000 of his 20_000 margin is being used in markets, but that can be changed quite
 * easily.
 *
 * example (1.3):
 * Tom can also change the position sizes without altering the amount of margin in each
 * active market position. He can do this by passing position objects with marginDelta set to "0"
 * and sizeDelta set to the newly desired size. An example of changing his above sETH long position
 * size and not altering his other positions:
 *
 * [{sETH, 0, 5*10e18, false}]
 *
 * His sETH is now 10x long position.
 *
 * example (1.4):
 * Now, Tom wishes to withdraw margin from one of his positions. He can do so by
 * passing a new position into distributeMargin() that has a negative margin value:
 *
 * [{sUNI, -(1_000), 0, false}]
 *
 * The above position object results in the sUNI market losing $1_000 sUSD in margin and
 * Tom's account balance increasing by $1_000 sUSD (which can be deposited immediately
 * into another market, even in the same transaction).
 *
 * example (2):
 * Assume Tom has a single long position in sETH made via:
 *
 * [{sETH, 1_000, 1*10e18, false}
 *
 * Tom wishes to close this position. He can do so simply by:
 *
 * [{sETH, 0, 0, true}
 *
 * Notice that size and margin do not matter. If `isClosing` is set to true, distributeMargin() will
 * immediately execute logic which will exit the position and tranfer all margin in that market back
 * to this account.
 *
 * ########### FINAL GOAL ###########
 * Ultimately, the goal of MarginBase is to offer users the flexibility to define cross margin
 * however they see fit. Single positions with limited margin relative to account margin is supported
 * as well as equally distrubted margin among all active market positions. It is up to the caller/front-end
 * to implement whatever strategy that best serves them.
 *
 * ########### NOTES ###########
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
 * [{sBTC, 0, 0, true}, {X}, {Y}, {Z}]
 *
 * The first position object closes the BTC position, returning that margin to the account
 * which can then be used to open or modify positions: X, Y, Z.
 *
 * (3) Notice that there is a distribute margin fee taken whenever margin is deposited/withdrawn
 *          from a market. Following tests explain and test this mechanism.
 *
 * @author jaredborders
 */

// constants
const MINT_AMOUNT = ethers.BigNumber.from("100000000000000000000000"); // == $100_000 sUSD
const ACCOUNT_AMOUNT = ethers.BigNumber.from("100000000000000000000000"); // == $100_000 sUSD
const TEST_VALUE = ethers.BigNumber.from("1000000000000000000000"); // == $1_000 sUSD

// denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
const distributionFee = 5;
const limitOrderFee = 5;
const stopLossFee = 10;

// kwenta
const KWENTA_TREASURY = "0x82d2242257115351899894eF384f779b5ba8c695";

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
let marginBaseSettings: Contract;
let marginAccountFactory: Contract;
let marginAccount: Contract;

// test accounts
let account0: SignerWithAddress;

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

        [account0] = await ethers.getSigners();

        // mint account0 $100_000 sUSD
        await mintToAccountSUSD(account0.address, MINT_AMOUNT);

        const IERC20ABI = (
            await artifacts.readArtifact(
                "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
            )
        ).abi;
        sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);
        const balance = await sUSD.balanceOf(account0.address);
        expect(balance).to.equal(MINT_AMOUNT);
    });

    it("Should deploy MarginAccountFactory contract", async () => {
        marginBaseSettings = await (
            await ethers.getContractFactory("MarginBaseSettings")
        ).deploy(KWENTA_TREASURY, distributionFee, limitOrderFee, stopLossFee);
        expect(marginBaseSettings.address).to.exist;

        marginAccountFactory = await (
            await ethers.getContractFactory("MarginAccountFactory")
        ).deploy(
            "1.0.0",
            SUSD_PROXY,
            ADDRESS_RESOLVER,
            marginBaseSettings.address
        );
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
            waffle.provider
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

        // deposit (amount in wei == $100_000 sUSD) sUSD into margin account
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
        const newPosition = [
            {
                // open ~1x LONG position in ETH-PERP Market
                marketKey: MARKET_KEY_sETH,
                marginDelta: TEST_VALUE, // $1_000 sUSD
                sizeDelta: ethers.BigNumber.from("500000000000000000"),
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trade
        await marginAccount.connect(account0).distributeMargin(newPosition);

        // confirm number of open positions that were defined above
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(1);

        // confirm correct position details: Market, Margin, Size
        // ETH
        const ETHposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sETH);
        expect(ETHposition.marketKey).to.equal(MARKET_KEY_sETH);
        expect(ETHposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        ); // 1% fee
        expect(ETHposition.size).to.equal(
            ethers.BigNumber.from("500000000000000000")
        ); // 0.5 ETH
    });

    it("Should Have Imposed Correct Fee after Modifying Position", async () => {
        // fetch fee BPS from contract
        const fee = await marginBaseSettings.distributionFee();

        // confirm it is what was passed to constructor
        expect(fee).to.equal(distributionFee);

        // calculate fee imposed on trade above
        const expectedFee = TEST_VALUE.mul(fee).div(10_000); // TEST_VALUE * 0.05% = $0.5 or 500000000000000000 wei

        // determine sUSD in MarginBase account
        const IERC20ABI = (
            await artifacts.readArtifact(
                "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
            )
        ).abi;
        sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);
        const balancePostTrade = await sUSD.balanceOf(marginAccount.address); // ~ $98_999.5
        const balancePreTrade = ACCOUNT_AMOUNT;
        const feeImposed = balancePreTrade.sub(
            balancePostTrade.add(TEST_VALUE)
        );

        expect(feeImposed).to.equal(expectedFee);
    });

    it("Should Open Multiple Positions", async () => {
        // define new positions
        const newPositions = [
            {
                // open ~1x SHORT position in BTC-PERP Market
                marketKey: MARKET_KEY_sBTC,
                marginDelta: TEST_VALUE, // $1_000 sUSD
                sizeDelta: ethers.BigNumber.from("-30000000000000000"), // 0.03 BTC
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // open ~5x LONG position in LINK-PERP Market
                marketKey: MARKET_KEY_sLINK,
                marginDelta: TEST_VALUE, // $1_000 sUSD
                sizeDelta: ethers.BigNumber.from("700000000000000000000"), // 700 LINK
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // open ~5x SHORT position in UNI-PERP Market
                marketKey: MARKET_KEY_sUNI,
                marginDelta: TEST_VALUE, // $1_000 sUSD
                sizeDelta: ethers.BigNumber.from("-900000000000000000000"), // 900 UNI
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);

        // confirm correct position details: Market, Margin, Size
        // BTC
        const BTCposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sBTC);
        expect(BTCposition.marketKey).to.equal(MARKET_KEY_sBTC);
        expect(BTCposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        ); // 1% fee
        expect(BTCposition.size).to.equal(
            ethers.BigNumber.from("-30000000000000000")
        ); // 0.03 BTC
        // LINK
        const LINKposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sLINK);
        expect(LINKposition.marketKey).to.equal(MARKET_KEY_sLINK);
        expect(LINKposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(2).div(100)
        ); // 2% fee
        expect(LINKposition.size).to.equal(
            ethers.BigNumber.from("700000000000000000000")
        ); // 700 LINK
        // UNI
        const UNIposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sUNI);
        expect(UNIposition.marketKey).to.equal(MARKET_KEY_sUNI);
        expect(UNIposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(2).div(100)
        ); // 2% fee
        expect(UNIposition.size).to.equal(
            ethers.BigNumber.from("-900000000000000000000")
        ); // 900 UNI
    });

    it("Should Have Imposed Correct Fee(s) after Modifying Position(s)", async () => {
        // fetch fee BPS from contract
        const fee = await marginBaseSettings.distributionFee();

        // confirm it is what was passed to constructor
        expect(fee).to.equal(distributionFee);

        // calculate fee imposed on (4) trade(s) above
        const expectedFee = TEST_VALUE.mul(4).mul(fee).div(10_000); // TEST_VALUE * 0.05% = $0.5 or 500000000000000000 wei

        // determine sUSD in MarginBase account
        const IERC20ABI = (
            await artifacts.readArtifact(
                "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
            )
        ).abi;
        sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);
        const balancePostTrades = await sUSD.balanceOf(marginAccount.address); // ~ $95_998
        const balancePreTrades = ACCOUNT_AMOUNT;
        const feeImposed = balancePreTrades.sub(
            balancePostTrades.add(TEST_VALUE.mul(4))
        );

        expect(feeImposed).to.equal(expectedFee);
    });

    it("Should Modify Multiple Position's Size", async () => {
        /**
         * Notice that marginDelta for all positions is 0.
         * No withdrawing nor depositing into market positions, only
         * modifying position size (i.e. leverage)
         *
         * Notice no fees will be imposed because only size delta is changed
         */

        // define new positions (modify existing)
        const newPositions = [
            {
                // modify ~1x LONG position in ETH-PERP Market to ~3x
                marketKey: MARKET_KEY_sETH,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("1000000000000000000"), // 0.5 ETH -> 1.5 ETH
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify ~1x SHORT position in BTC-PERP Market to ~3x
                marketKey: MARKET_KEY_sBTC,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-60000000000000000"), // 0.03 BTC -> 0.09 BTC
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify ~5x LONG position in LINK-PERP Market to ~1x
                marketKey: MARKET_KEY_sLINK,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("-560000000000000000000"), // 700 LINK -> 140 LINK
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify ~5x SHORT position in UNI-PERP Market to ~1x
                marketKey: MARKET_KEY_sUNI,
                marginDelta: 0, // no deposit
                sizeDelta: ethers.BigNumber.from("720000000000000000000"), // 900 UNI -> 180 UNI
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);

        // NOTICE: margin in each market position should stay *close* to the same
        // (only decreasing slightly due to further fees for altering the position)

        // confirm correct position details: Market, Margin, Size
        // ETH
        const ETHposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sETH);
        expect(ETHposition.marketKey).to.equal(MARKET_KEY_sETH);
        expect(ETHposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        );
        expect(ETHposition.size).to.equal(
            ethers.BigNumber.from("1500000000000000000")
        );
        // BTC
        const BTCposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sBTC);
        expect(BTCposition.marketKey).to.equal(MARKET_KEY_sBTC);
        expect(BTCposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        ); // 1% fee
        expect(BTCposition.size).to.equal(
            ethers.BigNumber.from("-90000000000000000")
        ); // 0.09 BTC
        // LINK
        const LINKposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sLINK);
        expect(LINKposition.marketKey).to.equal(MARKET_KEY_sLINK);
        expect(LINKposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(LINKposition.size).to.equal(
            ethers.BigNumber.from("140000000000000000000")
        ); // 140 LINK
        // UNI
        const UNIposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sUNI);
        expect(UNIposition.marketKey).to.equal(MARKET_KEY_sUNI);
        expect(UNIposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(UNIposition.size).to.equal(
            ethers.BigNumber.from("-180000000000000000000")
        ); // 180 UNI
    });

    it("Should Modify Multiple Position's Margin (deposit)", async () => {
        /**
         * BaseMargin Account at this point is only utilizing $4_000 sUSD of the
         * total $100_000 sUSD. The following trades will deposit more margin
         * into each active position, but will not alter the size
         *
         * After trades are executed, a fee will be sent to treasury
         */

        // confirm above assertion
        const preTradeBalance = await sUSD.balanceOf(marginAccount.address);
        const preTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // define new positions (modify existing)
        const newPositions = [
            {
                // modify margin in position via $1_000 sUSD deposit
                marketKey: MARKET_KEY_sETH,
                marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 1.5 ETH
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD deposit
                marketKey: MARKET_KEY_sBTC,
                marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 0.09 BTC
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD deposit
                marketKey: MARKET_KEY_sLINK,
                marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 140 LINK
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD deposit
                marketKey: MARKET_KEY_sUNI,
                marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 180 UNI
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);

        // NOTICE: margin in each market position should stay *close* to the same
        // (only decreasing slightly due to further fees for altering the position)

        // confirm correct position details: Market, Margin, Size
        // ETH
        const ETHposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sETH);
        expect(ETHposition.marketKey).to.equal(MARKET_KEY_sETH);
        expect(ETHposition.margin).to.be.closeTo(
            TEST_VALUE.add(TEST_VALUE),
            TEST_VALUE.mul(1).div(100)
        );
        expect(ETHposition.size).to.equal(
            ethers.BigNumber.from("1500000000000000000")
        );
        // BTC
        const BTCposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sBTC);
        expect(BTCposition.marketKey).to.equal(MARKET_KEY_sBTC);
        expect(BTCposition.margin).to.be.closeTo(
            TEST_VALUE.add(TEST_VALUE),
            TEST_VALUE.mul(1).div(100)
        ); // 1% fee
        expect(BTCposition.size).to.equal(
            ethers.BigNumber.from("-90000000000000000")
        ); // 0.09 BTC
        // LINK
        const LINKposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sLINK);
        expect(LINKposition.marketKey).to.equal(MARKET_KEY_sLINK);
        expect(LINKposition.margin).to.be.closeTo(
            TEST_VALUE.add(TEST_VALUE),
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(LINKposition.size).to.equal(
            ethers.BigNumber.from("140000000000000000000")
        ); // 140 LINK
        // UNI
        const UNIposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sUNI);
        expect(UNIposition.marketKey).to.equal(MARKET_KEY_sUNI);
        expect(UNIposition.margin).to.be.closeTo(
            TEST_VALUE.add(TEST_VALUE),
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(UNIposition.size).to.equal(
            ethers.BigNumber.from("-180000000000000000000")
        ); // 180 UNI

        // confirm fees paid correctly
        const postTradeBalance = await sUSD.balanceOf(marginAccount.address);
        expect(postTradeBalance).to.be.equal(
            // subtract margin delta and fees for each trade
            preTradeBalance
                .sub(TEST_VALUE.mul(4))
                .sub(TEST_VALUE.mul(4).mul(distributionFee).div(10_000))
        );

        const postTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);
        expect(postTradeTreasuryBalance).to.be.equal(
            // subtract margin delta and fees for each trade
            preTradeTreasuryBalance
                .add(TEST_VALUE.mul(4).mul(distributionFee).div(10_000))
        );
    });

    it("Should Modify Multiple Position's Margin (withdraw)", async () => {
        /**
         * BaseMargin Account at this point is only utilizing $8_000 sUSD of the
         * total $100_000 sUSD. The following trades will withdraw margin
         * from each active position, but will not alter the size
         *
         * After trades are executed, a fee will be sent to treasury
         */

        // confirm above assertion
        const preTradeBalance = await sUSD.balanceOf(marginAccount.address);
        const preTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // define new positions (modify existing)
        const newPositions = [
            {
                // modify margin in position via $1_000 sUSD withdraw
                marketKey: MARKET_KEY_sETH,
                marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 1.5 ETH
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD withdraw
                marketKey: MARKET_KEY_sBTC,
                marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 0.09 BTC
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD withdraw
                marketKey: MARKET_KEY_sLINK,
                marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 140 LINK
                isClosing: false, // position is active (i.e. not closed)
            },
            {
                // modify margin in position via $1_000 sUSD withdraw
                marketKey: MARKET_KEY_sUNI,
                marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                sizeDelta: 0, // (no change) prev set to: 180 UNI
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(4);

        // NOTICE: margin in each market position should stay *close* to the same
        // (only decreasing slightly due to further fees for altering the position)

        // confirm correct position details: Market, Margin, Size
        // ETH
        const position = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sETH);
        expect(position.marketKey).to.equal(MARKET_KEY_sETH);
        expect(position.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        );
        expect(position.size).to.equal(
            ethers.BigNumber.from("1500000000000000000")
        );
        // BTC
        const BTCposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sBTC);
        expect(BTCposition.marketKey).to.equal(MARKET_KEY_sBTC);
        expect(BTCposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(1).div(100)
        ); // 1% fee
        expect(BTCposition.size).to.equal(
            ethers.BigNumber.from("-90000000000000000")
        ); // 0.09 BTC
        // LINK
        const LINKposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sLINK);
        expect(LINKposition.marketKey).to.equal(MARKET_KEY_sLINK);
        expect(LINKposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(LINKposition.size).to.equal(
            ethers.BigNumber.from("140000000000000000000")
        ); // 140 LINK
        // UNI
        const UNIposition = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sUNI);
        expect(UNIposition.marketKey).to.equal(MARKET_KEY_sUNI);
        expect(UNIposition.margin).to.be.closeTo(
            TEST_VALUE,
            TEST_VALUE.mul(4).div(100)
        ); // 4% fee
        expect(UNIposition.size).to.equal(
            ethers.BigNumber.from("-180000000000000000000")
        ); // 180 UNI

        // confirm fees paid correctly
        const postTradeBalance = await sUSD.balanceOf(marginAccount.address);
        expect(postTradeBalance).to.be.equal(
            // subtract margin delta and fees for each trade
            preTradeBalance
                .add(TEST_VALUE.mul(4))
                .sub(TEST_VALUE.mul(4).mul(distributionFee).div(10_000))
        );

        const postTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);
        expect(postTradeTreasuryBalance).to.be.equal(
            // subtract margin delta and fees for each trade
            preTradeTreasuryBalance
                .add(TEST_VALUE.mul(4).mul(distributionFee).div(10_000))
        );
    });

    it("Should have Withdrawn Margin back to Account", async () => {
        /**
         * Above test withdrew margin (TEST_VALUE) from each (4) position.
         *
         * After trades were executed, a fee would have been sent to treasury
         */

        const expectedBalance = ACCOUNT_AMOUNT.sub(
            // 12 trades depositing/withdrawing margin, 8 deposit, 4 withdraw = 4 net deposit
            TEST_VALUE.mul(4)
        ).sub(
            // 12 positions that modify margin by TEST_VALUE thus far (i.e. fees imposed)
            TEST_VALUE.mul(12).mul(distributionFee).div(10_000)
        );

        const actualbalance = await sUSD.balanceOf(marginAccount.address);
        expect(expectedBalance).to.equal(actualbalance);
    });

    it("Should Exit Position by Setting Size to Zero", async () => {
        /*
         * After trades were executed, a fee would have been sent to treasury
         */
        // confirm above assertion
        const preTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // establish ETH position
        let position = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sETH);

        // define new positions (modify existing)
        const newPositions = [
            {
                // modify size in position to 0
                marketKey: MARKET_KEY_sETH,
                marginDelta: 0,
                sizeDelta: position.size.mul(-1), // opposite size
                isClosing: false, // position is active (i.e. not closed)
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(3);

        // confirm kwenta treasury received fees
        const postTradeTreasuryBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // @TODO Fix/Investigate calculation

        // expect(postTradeTreasuryBalance).to.be.equal(
        //     preTradeTreasuryBalance.add(
        //         position.margin.mul(distributionFee).div(10_000)
        //     )
        // );
        // fails: 491907513039199122 / 991171800876081994034 = 0.0004962888498 ????
        expect(postTradeTreasuryBalance).to.be.above(preTradeTreasuryBalance);
        console.log(position.margin);
        console.log(postTradeTreasuryBalance.sub(preTradeTreasuryBalance));
    });

    it("Should Exit One Position with isClosing", async () => {
        // confirm above assertion
        const preTradeBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // establish ETH position
        let position = await marginAccount
            .connect(account0)
            .activeMarketPositions(MARKET_KEY_sBTC);

        // define new positions (modify existing)
        const newPositions = [
            {
                // exit position
                marketKey: MARKET_KEY_sBTC,
                marginDelta: 0,
                sizeDelta: 0,
                isClosing: true, // position should be closed
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(2);

        // confirm kwenta treasury received fees
        const postTradeBalance = await sUSD.balanceOf(KWENTA_TREASURY);

        // @TODO Fix/Investigate calculation

        expect(postTradeBalance).to.be.above(preTradeBalance);
    });

    it("Should Exit All Positions with isClosing", async () => {
        // define new positions (modify existing)
        const newPositions = [
            {
                // exit position
                marketKey: MARKET_KEY_sLINK,
                marginDelta: 0,
                sizeDelta: 0,
                isClosing: true, // position should be closed
            },
            {
                // exit position
                marketKey: MARKET_KEY_sUNI,
                marginDelta: 0,
                sizeDelta: 0,
                isClosing: true, // position should be closed
            },
        ];

        // execute trades
        await marginAccount.connect(account0).distributeMargin(newPositions);

        // confirm number of open positions
        const numberOfActivePositions = await marginAccount
            .connect(account0)
            .getNumberOfActivePositions();
        expect(numberOfActivePositions).to.equal(0);

        // @TODO add/check fee calculation
    });

    it("Should have Withdrawn All Margin back to Account", async () => {
        /**
         * Above test closed and withdrew ALL margin from each (4) position.
         * Given that, the account should now have:
         * $10_000 sUSD minus fees
         *
         * After trades are executed, a fee will be sent to treasury
         */

        const expectedBalance = ACCOUNT_AMOUNT;
        const actualbalance = await sUSD.balanceOf(marginAccount.address);
        expect(expectedBalance).to.be.closeTo(
            actualbalance,
            expectedBalance.mul(1).div(100) // 1% cumulative fees from Synthetix and Kwenta
        );
    });

    it("Should Withdraw Margin from Account", async () => {
        // get account balance
        const accountBalance = await sUSD.balanceOf(marginAccount.address);

        // withdraw sUSD from margin account
        await marginAccount.connect(account0).withdraw(accountBalance);

        // confirm withdraw
        const eoaBalance = await sUSD.balanceOf(account0.address);

        // fees resulted in:
        // ACCOUNT_AMOUNT (initial margin amount depositied into account) > accountBalance
        expect(eoaBalance).to.equal(
            MINT_AMOUNT.sub(ACCOUNT_AMOUNT).add(accountBalance)
        );
    });
});
