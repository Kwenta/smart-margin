/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { Contract } from "ethers";
import { mintToAccountSUSD } from "../utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";

dotenv.config();

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
        describe("Opening Positions", () => {
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
        });

        describe("Closing Positions", () => {
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

            it("Should close single position", async () => {
                const sizeDelta = ethers.BigNumber.from("500000000000000000");

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

            it("Should close multiple positions", async () => {
                const btcSizeDelta =
                    ethers.BigNumber.from("-30000000000000000"); // 0.03 BTC
                const linkSizeDelta = ethers.BigNumber.from(
                    "700000000000000000000"
                ); // 700 LINK
                const uniSizeDelta = ethers.BigNumber.from(
                    "-900000000000000000000"
                ); // 900 UNI
                const ethSizeDelta =
                    ethers.BigNumber.from("500000000000000000"); // 0.5 ETH

                // define new positions
                const openingPositions = [
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
                    {
                        // open ~1x LONG position in ETH-PERP Market
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // $1_000 sUSD
                        sizeDelta: ethSizeDelta, // 0.5 ETH
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(openingPositions);

                // modify positions (will close two of the above)
                const closingPositions = [
                    {
                        // close ~1x SHORT position in BTC-PERP Market
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: 0,
                        sizeDelta: btcSizeDelta.mul(-1), // -0.03 BTC
                    },
                    {
                        // close ~5x SHORT position in UNI-PERP Market
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: 0,
                        sizeDelta: uniSizeDelta.mul(-1), // -900 UNI
                    },
                ];

                // execute trades (i.e. close positions)
                await marginAccount
                    .connect(account0)
                    .distributeMargin(closingPositions);

                // confirm correct position details:
                expect(
                    await marginAccount.getNumberOfInternalPositions()
                ).to.equal(2);

                /********** ACTIVE MARKETS **********/
                // LINK-PERP
                // (1) mapping is correct
                let marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sLINK
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sLINK);
                // (2) size and margin
                let position = await marginAccount.getPosition(
                    MARKET_KEY_sLINK
                );
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(linkSizeDelta);

                // ETH-PERP
                // (1) mapping is correct
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sETH
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sETH);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sETH);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(ethSizeDelta);

                /********** INACTIVE MARKETS **********/
                // @notice default value for mapping is 0

                // BTC-PERP
                // (1) mapping is correct
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sBTC
                );
                expect(marketKeyIndex).to.equal(0);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sBTC);
                expect(position.margin).to.equal(0);
                expect(position.size).to.equal(0);

                // UNI-PERP
                // (1) mapping is correct
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sUNI
                );
                expect(marketKeyIndex).to.equal(0);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sUNI);
                expect(position.margin).to.equal(0);
                expect(position.size).to.equal(0);
            });

            it("Should withdraw all margin to account after closing position", async () => {
                const sizeDelta = ethers.BigNumber.from("500000000000000000");

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
            const ethSizeDelta = ethers.BigNumber.from("500000000000000000");
            const btcSizeDelta = ethers.BigNumber.from("-30000000000000000");
            const linkSizeDelta = ethers.BigNumber.from(
                "700000000000000000000"
            );
            const uniSizeDelta = ethers.BigNumber.from(
                "-900000000000000000000"
            );

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

                // open (4) positions
                // define new positions
                const openingPositions = [
                    {
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE,
                        sizeDelta: ethSizeDelta,
                    },
                    {
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE,
                        sizeDelta: btcSizeDelta,
                    },
                    {
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE,
                        sizeDelta: linkSizeDelta,
                    },
                    {
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE,
                        sizeDelta: uniSizeDelta,
                    },
                ];

                // execute trades
                await marginAccount
                    .connect(account0)
                    .distributeMargin(openingPositions);
            });

            it("Should Modify Multiple Position's Size", async () => {
                const newETHSizeDelta = ethers.BigNumber.from(
                    "1000000000000000000"
                );
                const newBTCSizeDelta =
                    ethers.BigNumber.from("-60000000000000000");
                const newLINKSizeDelta = ethers.BigNumber.from(
                    "-560000000000000000000"
                );
                const newUNISizeDelta = ethers.BigNumber.from(
                    "720000000000000000000"
                );

                // define new positions (modify existing)
                const newPositions = [
                    {
                        // modify ~1x LONG position in ETH-PERP Market to ~3x
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: 0, // no deposit
                        sizeDelta: newETHSizeDelta, // 0.5 ETH -> 1.5 ETH
                    },
                    {
                        // modify ~1x SHORT position in BTC-PERP Market to ~3x
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: 0, // no deposit
                        sizeDelta: newBTCSizeDelta, // 0.03 BTC -> 0.09 BTC
                    },
                    {
                        // modify ~5x LONG position in LINK-PERP Market to ~1x
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: 0, // no deposit
                        sizeDelta: newLINKSizeDelta, // 700 LINK -> 140 LINK
                    },
                    {
                        // modify ~5x SHORT position in UNI-PERP Market to ~1x
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: 0, // no deposit
                        sizeDelta: newUNISizeDelta, // 900 UNI -> 180 UNI
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

                // confirm correct position details:

                // ETH-PERP
                // (1) market exists internally
                let marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sETH
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sETH);
                // (2) size and margin
                let position = await marginAccount.getPosition(MARKET_KEY_sETH);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(
                    ethSizeDelta.add(newETHSizeDelta)
                );

                // BTC-PERP
                // (1) market exists internally
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sBTC
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sBTC);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sBTC);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(
                    btcSizeDelta.add(newBTCSizeDelta)
                );

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
                expect(position.size).to.equal(
                    linkSizeDelta.add(newLINKSizeDelta)
                );

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
                expect(position.size).to.equal(
                    uniSizeDelta.add(newUNISizeDelta)
                );
            });

            it("Should Modify Multiple Position's Margin (deposit)", async () => {
                const oldETHposition = await marginAccount.getPosition(
                    MARKET_KEY_sETH
                );
                const oldBTCposition = await marginAccount.getPosition(
                    MARKET_KEY_sBTC
                );
                const oldLINKposition = await marginAccount.getPosition(
                    MARKET_KEY_sLINK
                );
                const oldUNIposition = await marginAccount.getPosition(
                    MARKET_KEY_sUNI
                );

                // define new positions (modify existing)
                const newPositions = [
                    {
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE, // deposit TEST_VALUE
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~1x SHORT position in BTC-PERP Market to ~3x
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE, // deposit TEST_VALUE
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~5x LONG position in LINK-PERP Market to ~1x
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE, // deposit TEST_VALUE
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~5x SHORT position in UNI-PERP Market to ~1x
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE, // deposit TEST_VALUE
                        sizeDelta: 0, // no change in size
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

                // confirm correct position details:

                // ETH-PERP
                // (1) market exists internally
                let marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sETH
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sETH);
                // (2) size and margin
                let position = await marginAccount.getPosition(MARKET_KEY_sETH);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(oldETHposition.margin);
                expect(position.size).to.equal(ethSizeDelta);

                // BTC-PERP
                // (1) market exists internally
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sBTC
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sBTC);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sBTC);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(oldBTCposition.margin);
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
                expect(position.margin).to.be.above(oldLINKposition.margin);
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
                expect(position.margin).to.be.above(oldUNIposition.margin);
                expect(position.size).to.equal(uniSizeDelta);
            });

            it("Should Modify Multiple Position's Margin (withdraw)", async () => {
                const oldETHposition = await marginAccount.getPosition(
                    MARKET_KEY_sETH
                );
                const oldBTCposition = await marginAccount.getPosition(
                    MARKET_KEY_sBTC
                );
                const oldLINKposition = await marginAccount.getPosition(
                    MARKET_KEY_sLINK
                );
                const oldUNIposition = await marginAccount.getPosition(
                    MARKET_KEY_sUNI
                );

                // define new positions (modify existing)
                const newPositions = [
                    {
                        marketKey: MARKET_KEY_sETH,
                        marginDelta: TEST_VALUE.div(8).mul(-1), // withdraw (TEST_VALUE / 8)
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~1x SHORT position in BTC-PERP Market to ~3x
                        marketKey: MARKET_KEY_sBTC,
                        marginDelta: TEST_VALUE.div(8).mul(-1), // withdraw (TEST_VALUE / 8)
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~5x LONG position in LINK-PERP Market to ~1x
                        marketKey: MARKET_KEY_sLINK,
                        marginDelta: TEST_VALUE.div(8).mul(-1), // withdraw (TEST_VALUE / 8)
                        sizeDelta: 0, // no change in size
                    },
                    {
                        // modify ~5x SHORT position in UNI-PERP Market to ~1x
                        marketKey: MARKET_KEY_sUNI,
                        marginDelta: TEST_VALUE.div(8).mul(-1), // withdraw (TEST_VALUE / 8)
                        sizeDelta: 0, // no change in size
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

                // confirm correct position details:

                // ETH-PERP
                // (1) market exists internally
                let marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sETH
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sETH);
                // (2) size and margin
                let position = await marginAccount.getPosition(MARKET_KEY_sETH);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.below(oldETHposition.margin);
                expect(position.size).to.equal(ethSizeDelta);

                // BTC-PERP
                // (1) market exists internally
                marketKeyIndex = await marginAccount.marketKeyIndex(
                    MARKET_KEY_sBTC
                );
                expect(
                    await marginAccount.activeMarketKeys(marketKeyIndex)
                ).to.equal(MARKET_KEY_sBTC);
                // (2) size and margin
                position = await marginAccount.getPosition(MARKET_KEY_sBTC);
                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.below(oldBTCposition.margin);
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
                expect(position.margin).to.be.below(oldLINKposition.margin);
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
                expect(position.margin).to.be.below(oldUNIposition.margin);
                expect(position.size).to.equal(uniSizeDelta);
            });
        });
    });

    describe("Batch Tx", () => {
        before("Fork Network", async () => {
            await forkAtBlock(9000000);
            // mint sUSD to test accounts, and deploy contracts
            await setup();
            await deployMarginBaseAccountForEOA(account0);
        });

        it("Should Deposit and open single position in one tx", async () => {
            const sizeDelta = ethers.BigNumber.from("500000000000000000");

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

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
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

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
});
