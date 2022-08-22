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
const MINT_AMOUNT = ethers.BigNumber.from("110000000000000000000000"); // == $110_000 sUSD
const ACCOUNT_AMOUNT = ethers.BigNumber.from("100000000000000000000000"); // == $100_000 sUSD
const TEST_VALUE = ethers.BigNumber.from("1000000000000000000000"); // == $1_000 sUSD
const MAX_BPS = 10_000;

// denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
const tradeFee = 5;
const limitOrderFee = 5;
const stopLossFee = 10;

// kwenta
const KWENTA_TREASURY = "0x82d2242257115351899894eF384f779b5ba8c695";

// synthetix (ReadProxyAddressResolver)
const ADDRESS_RESOLVER = "0x1Cb059b7e74fD21665968C908806143E744D5F30";

// synthetix: proxy
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";
let sUSD: Contract;

// synthetix: market keys
// see: https://github.com/Synthetixio/synthetix/blob/develop/publish/deployed/mainnet-ovm/futures-markets.json
const MARKET_KEY_sETH = ethers.utils.formatBytes32String("sETH");
const MARKET_KEY_sBTC = ethers.utils.formatBytes32String("sBTC");
const MARKET_KEY_sLINK = ethers.utils.formatBytes32String("sLINK");
const MARKET_KEY_sUNI = ethers.utils.formatBytes32String("sUNI");

// gelato
const GELATO_OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";

// cross margin
let marginBaseSettings: Contract;
let marginAccountFactory: Contract;
let marginAccount: Contract;

// test accounts
let account0: SignerWithAddress;
let account1: SignerWithAddress;

/*///////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
///////////////////////////////////////////////////////////////*/

/**
 * @notice fork network at block number given
 */
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

/**
 * @notice deploy MarginBaseAccount
 * @dev requires setup() be called prior
 */
const deployMarginBaseAccountForEOA = async (account: SignerWithAddress) => {
    const tx = await marginAccountFactory.connect(account).newAccount();
    const rc = await tx.wait(); // 0ms, as tx is already confirmed
    const event = rc.events.find(
        (event: { event: string }) => event.event === "NewAccount"
    );
    const [, marginAccountAddress] = event.args;
    const MarginBaseABI = (
        await artifacts.readArtifact("contracts/MarginBase.sol:MarginBase")
    ).abi;
    marginAccount = new ethers.Contract(
        marginAccountAddress,
        MarginBaseABI,
        waffle.provider
    );
};

/**
 * @notice mint sUSD to test accounts, and deploy contracts
 */
const setup = async () => {
    // get signers
    [account0, account1] = await ethers.getSigners();

    // mint account0 $100_000 sUSD
    await mintToAccountSUSD(account0.address, MINT_AMOUNT);

    // mint account1 $100_000 sUSD
    await mintToAccountSUSD(account1.address, MINT_AMOUNT);

    // Deploy Settings
    const MarginBaseSettings = await ethers.getContractFactory(
        "MarginBaseSettings"
    );
    marginBaseSettings = await MarginBaseSettings.deploy(
        KWENTA_TREASURY,
        tradeFee,
        limitOrderFee,
        stopLossFee
    );

    // Deploy Account Factory
    const MarginAccountFactory = await ethers.getContractFactory(
        "MarginAccountFactory"
    );
    marginAccountFactory = await MarginAccountFactory.deploy(
        "1.0.0",
        SUSD_PROXY,
        ADDRESS_RESOLVER,
        marginBaseSettings.address,
        GELATO_OPS
    );
};

/*///////////////////////////////////////////////////////////////
                                TESTS
///////////////////////////////////////////////////////////////*/

describe("Integration: Test Cross Margin", () => {
    describe("Settings & Account Factory Deployment", () => {
        before("Fork Network", async () => {
            await forkAtBlock(9000000);
        });
        beforeEach("Setup", async () => {
            // mint sUSD to test accounts, and deploy contracts
            await setup();
        });

        it("Test signers should have sUSD", async () => {
            const IERC20ABI = (
                await artifacts.readArtifact(
                    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
                )
            ).abi;
            sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);

            // account0 balance
            let balance = await sUSD.balanceOf(account0.address);
            expect(balance).to.equal(MINT_AMOUNT);

            // account1 balance
            balance = await sUSD.balanceOf(account1.address);
            expect(balance).to.equal(MINT_AMOUNT);
        });

        it("Should have deployed MarginBaseSettings contract", async () => {
            expect(marginBaseSettings.address).to.exist;
        });

        it("Should have deployed MarginAccountFactory contract", async () => {
            expect(marginAccountFactory.address).to.exist;
        });
    });

    describe("Margin Account Initialization", () => {
        let owner: string;
        let marginAccountAddress: string;
        let actualOwner: string;

        before("Fork Network", async () => {
            await forkAtBlock(9000000);
        });

        // see `deployMarginBaseAccountForEOA()`; does the same thing but does not check ownership
        it("Should deploy MarginBase contract and initialize it", async () => {
            // mint sUSD to test accounts, and deploy contracts
            await setup();

            const tx = await marginAccountFactory
                .connect(account0)
                .newAccount();
            const rc = await tx.wait(); // 0ms, as tx is already confirmed
            const event = rc.events.find(
                (event: { event: string }) => event.event === "NewAccount"
            );
            [owner, marginAccountAddress] = event.args;
            const MarginBaseABI = (
                await artifacts.readArtifact(
                    "contracts/MarginBase.sol:MarginBase"
                )
            ).abi;
            marginAccount = new ethers.Contract(
                marginAccountAddress,
                MarginBaseABI,
                waffle.provider
            );
            expect(marginAccount.address).to.exist;
        });

        it("MarginBase margin asset is sUSD", async () => {
            // check sUSD is margin asset
            const marginAsset = await marginAccount
                .connect(account0)
                .marginAsset();
            expect(marginAsset).to.equal(SUSD_PROXY);
        });

        it("MarginBase owned by deployer", async () => {
            // check owner is deployer (i.e. account0)
            actualOwner = await marginAccount.connect(account0).owner();
            expect(owner).to.equal(actualOwner);
            expect(actualOwner).to.equal(account0.address);
        });
    });

    describe("Deposit and Withdraw margin from account", () => {
        before("Fork Network", async () => {
            await forkAtBlock(9000000);
        });
        beforeEach("Setup", async () => {
            // mint sUSD to test accounts, and deploy contracts
            await setup();
            await deployMarginBaseAccountForEOA(account0);
        });

        it("Should Approve Allowance and Deposit Margin into Account", async () => {
            // approve allowance for marginAccount to spend
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // deposit sUSD into margin account
            await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);

            // confirm deposit
            const balance = await sUSD.balanceOf(marginAccount.address);
            expect(balance).to.equal(ACCOUNT_AMOUNT);
        });

        it("Should Withdraw Margin from Account", async () => {
            const preBalance = await sUSD.balanceOf(account0.address);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // deposit sUSD into margin account
            await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);

            // withdraw sUSD into margin account
            await marginAccount.connect(account0).withdraw(ACCOUNT_AMOUNT);

            // confirm deposit
            const marginAccountBalance = await sUSD.balanceOf(
                marginAccount.address
            );
            expect(marginAccountBalance).to.equal(0);

            const postBalance = await sUSD.balanceOf(account0.address);
            expect(preBalance).to.equal(postBalance);
        });
    });

    /**
     * For the following tests, the approximated leverage (1x, 3x, 5x, etc)
     * is not crucial. Aapproximations added just for clarity.
     *
     * The token prices at this current block (9000000) are only estimated.
     *
     * What is important are the multiples which change when new or modified
     * positions are passed to the contract
     * (i.e. did size, margin, etc. change appropriately)
     */

    describe("Distributing Margin", () => {
        describe("Opening and Closing Positions", () => {
            const sizeDelta = ethers.BigNumber.from("500000000000000000");

            before("Fork Network", async () => {
                await forkAtBlock(9000000);
            });
            beforeEach("Setup", async () => {
                // mint sUSD to test accounts, and deploy contracts
                await setup();
                await deployMarginBaseAccountForEOA(account0);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(account0)
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);
            });

            it("Should open single position", async () => {
                // define new positions
                const newPosition = [
                    {
                        // open ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: sizeDelta,
                    },
                ];

                // execute trade
                await marginAccount
                    .connect(account0)
                    .distributeMargin(newPosition);

                // confirm number of open internal positions that were defined above
                const numberOfInternalPositions = await marginAccount
                    .connect(account0)
                    .getNumberOfInternalPositions();
                expect(numberOfInternalPositions).to.equal(1);

                // confirm correct position details:
                // (1) market exists internally
                const marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sETH
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sETH);
                // (2) size and margin
                const position = await marginAccount
                    .connect(account0)
                    .getPosition(MARKET_KEY_sETH);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(sizeDelta);
            });

            it("Should close single position", async () => {
                const openingPosition = [
                    {
                        // open ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: sizeDelta,
                    },
                ];

                // execute trade
                await marginAccount
                    .connect(account0)
                    .distributeMargin(openingPosition);

                // position will close previously opened one
                const closingPosition = [
                    {
                        // close ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: 0,
                        sizeDelta: sizeDelta.mul(-1),
                    },
                ];

                // execute trade
                await marginAccount
                    .connect(account0)
                    .distributeMargin(closingPosition);

                // confirm correct position details:
                // (1) market does not exist internally
                expect(
                    await marginAccount.getNumberOfInternalPositions()
                ).to.equal(0);
                // (2) size and margin
                const position = await marginAccount
                    .connect(account0)
                    .getPosition(MARKET_KEY_sETH);
                expect(position.margin).to.equal(0);
                expect(position.size).to.equal(0);
            });

            it("Should open multiple positions", async () => {
                const btcSizeDelta =
                    ethers.BigNumber.from("-30000000000000000"); // 0.03 BTC
                const linkSizeDelta = ethers.BigNumber.from(
                    "700000000000000000000"
                ); // 700 LINK
                const uniSizeDelta = ethers.BigNumber.from(
                    "-900000000000000000000"
                ); // 900 UNI

                // define new positions
                const newPositions = [
                    {
                        // open ~1x SHORT position in BTC-PERP Market
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: btcSizeDelta, // 0.03 BTC
                    },
                    {
                        // open ~5x LONG position in LINK-PERP Market
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: linkSizeDelta, // 700 LINK
                    },
                    {
                        // open ~5x SHORT position in UNI-PERP Market
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: uniSizeDelta, // 900 UNI
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(newPositions);

                // confirm number of open internal positions that were defined above
                const numberOfInternalPositions = await marginAccount
                    .connect(account0)
                    .getNumberOfInternalPositions();
                expect(numberOfInternalPositions).to.equal(3);

                // confirm correct position details:

                // BTC-PERP
                // (1) market exists internally
                let marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sBTC
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sBTC);
                // (2) size and margin
                let position = await marginAccount.getPosition(MARKET_KEY_sBTC);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(btcSizeDelta);

                // LINK-PERP
                // (1) market exists internally
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sLINK
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sLINK);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sLINK);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(linkSizeDelta);

                // UNI-PERP
                // (1) market exists internally
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sUNI
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sUNI);
                // (2) size and margin
                position = await marginAccount
                    .connect(account0)
                    .getPosition(MARKET_KEY_sUNI);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(uniSizeDelta);
            });

            it("Should withdraw all margin to account after closing position", async () => {
                const openingPosition = [
                    {
                        // open ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: sizeDelta,
                    },
                ];

                const preBalance = await sUSD.balanceOf(marginAccount.address);

                // execute trade
                await marginAccount
                    .connect(account0)
                    .distributeMargin(openingPosition);

                const postOpeningTradeBalance = await sUSD.balanceOf(
                    marginAccount.address
                );

                // position will close previously opened one
                const closingPosition = [
                    {
                        // close ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: 0,
                        sizeDelta: sizeDelta.mul(-1),
                    },
                ];

                // execute trade
                await marginAccount
                    .connect(account0)
                    .distributeMargin(closingPosition);

                const postClosingTradeBalance = await sUSD.balanceOf(
                    marginAccount.address
                );

                expect(preBalance).to.be.above(postOpeningTradeBalance);
                expect(postClosingTradeBalance).to.be.above(
                    postOpeningTradeBalance
                );
            });
        });

        describe("Modifying Positions", () => {
            before("Fork Network", async () => {
                await forkAtBlock(9000000);
            });
            beforeEach("Setup", async () => {
                // mint sUSD to test accounts, and deploy contracts
                await setup();
                await deployMarginBaseAccountForEOA(account1);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(account0)
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);
            });

            it.skip("Should Modify Multiple Position's Size", async () => {
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
                        sizeDelta: ethers.BigNumber.from(
                            "-560000000000000000000"
                        ), // 700 LINK -> 140 LINK
                    },
                    {
                        // modify ~5x SHORT position in UNI-PERP Market to ~1x
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: 0, // no deposit
                        sizeDelta: ethers.BigNumber.from(
                            "720000000000000000000"
                        ), // 900 UNI -> 180 UNI
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(account0)
                    .getNumberOfInternalPositions();
                expect(numberOfActivePositions).to.equal(4);

                // NOTICE: margin in each market position should stay *close* to the same
                // (only decreasing slightly due to further Synthetix fees for altering the position)

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

            it.skip("Should Modify Multiple Position's Margin (deposit)", async () => {
                /**
                 * BaseMargin Account at this point is only utilizing $4_000 sUSD of the
                 * total $100_000 sUSD. The following trades will deposit more margin
                 * into each active position, but will not alter the size
                 */

                // define new positions (modify existing)
                const newPositions = [
                    {
                        // modify margin in position via $1_000 sUSD deposit
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 1.5 ETH
                    },
                    {
                        // modify margin in position via $1_000 sUSD deposit
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 0.09 BTC
                    },
                    {
                        // modify margin in position via $1_000 sUSD deposit
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 140 LINK
                    },
                    {
                        // modify margin in position via $1_000 sUSD deposit
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE, // $1_000 sUSD -> $2_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 180 UNI
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(account0)
                    .getNumberOfInternalPositions();
                expect(numberOfActivePositions).to.equal(4);

                // NOTICE: margin in each market position should stay *close* to the same
                // (only decreasing slightly due to further Synthetix fees for altering the position)

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
            });

            it.skip("Should Modify Multiple Position's Margin (withdraw)", async () => {
                /**
                 * BaseMargin Account at this point is only utilizing $8_000 sUSD of the
                 * total $100_000 sUSD. The following trades will withdraw margin
                 * from each active position, but will not alter the size
                 */

                // define new positions (modify existing)
                const newPositions = [
                    {
                        // modify margin in position via $1_000 sUSD withdraw
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 1.5 ETH
                    },
                    {
                        // modify margin in position via $1_000 sUSD withdraw
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 0.09 BTC
                    },
                    {
                        // modify margin in position via $1_000 sUSD withdraw
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 140 LINK
                    },
                    {
                        // modify margin in position via $1_000 sUSD withdraw
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE.mul(-1), // $2_000 sUSD -> $1_000 sUSD
                        sizeDelta: 0, // (no change) prev set to: 180 UNI
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(account0)
                    .getNumberOfInternalPositions();
                expect(numberOfActivePositions).to.equal(4);

                // NOTICE: margin in each market position should stay *close* to the same
                // (only decreasing slightly due to further synthetix fees for altering the position)

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
            });
        });
    });

    describe("Batch Tx", () => {
        const sizeDelta = ethers.BigNumber.from("500000000000000000");

        before("Fork Network", async () => {
            await forkAtBlock(9000000);
            // mint sUSD to test accounts, and deploy contracts
            await setup();
            await deployMarginBaseAccountForEOA(account0);
        });

        it("Should Deposit and open single position in one tx", async () => {
            // approve allowance for marginAccount to spend
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, TEST_VALUE);

            // define new positions
            const newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(account0)
                .depositAndDistribute(TEST_VALUE, newPosition);

            // confirm number of open internal positions that were defined above
            const numberOfInternalPositions = await marginAccount
                .connect(account0)
                .getNumberOfInternalPositions();
            expect(numberOfInternalPositions).to.equal(1);

            // confirm correct position details:
            // (1) market exists internally
            const marketKeyIndex = await marginAccount.marketKeyIndex(
                MARKET_KEY_sETH
            );
            expect(
                await marginAccount.activeMarketKeys(marketKeyIndex)
            ).to.equal(MARKET_KEY_sETH);
            // (2) size and margin
            const position = await marginAccount
                .connect(account0)
                .getPosition(MARKET_KEY_sETH);
            // will not estimate exact value for margin
            // due to potential future fee changes (makes test brittle)
            expect(position.margin).to.be.above(0);
            expect(position.size).to.equal(sizeDelta);
        });
    });

    // @TODO simulate a situation where a position has been liquidated and a user
    // passes in a newActivePosition that specifies that same market
    // @TODO do this after hh refactor
});
