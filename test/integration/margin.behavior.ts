/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract, ContractReceipt } from "ethers";
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
// see:
// https://github.com/Synthetixio/synthetix/blob/develop/publish/deployed/mainnet-ovm/futures-markets.json
const MARKET_KEY_sETH = ethers.utils.formatBytes32String("sETH");
const MARKET_KEY_sBTC = ethers.utils.formatBytes32String("sBTC");
const MARKET_KEY_sLINK = ethers.utils.formatBytes32String("sLINK");
const MARKET_KEY_sUNI = ethers.utils.formatBytes32String("sUNI");

// market addresses at current block
const ETH_PERP_MARKET_ADDR = "0xf86048DFf23cF130107dfB4e6386f574231a5C65";

// gelato
const GELATO_OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";

// cross margin
let marginBaseSettings: Contract;
let marginAccountFactory: Contract;
let marginAccount: Contract;

// test account(s)
let accounts: SignerWithAddress[];

/*///////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
///////////////////////////////////////////////////////////////*/

/**
 *  Increases the time in the EVM.
 *  @param seconds Number of seconds to increase the time by
 */
const fastForward = async (seconds: number | BigNumber) => {
    // It's handy to be able to be able to pass big numbers in as we can just
    // query them from the contract, then send them back. If not changed to
    // a number, this causes much larger fast forwards than expected without error.
    if (ethers.BigNumber.isBigNumber(seconds)) seconds = seconds.toNumber();

    // And same with strings.
    if (typeof seconds === "string") seconds = parseFloat(seconds);

    await network.provider.send("evm_increaseTime", [seconds]);

    await network.provider.send("evm_mine");
    await network.provider.send("evm_mine");
};

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
    accounts = await ethers.getSigners();

    for (let index = 0; index < 30; index++) {
        // mint account0 $100_000 sUSD
        await mintToAccountSUSD(accounts[index].address, MINT_AMOUNT);
    }

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
    before("Fork Network", async () => {
        await forkAtBlock(9000000);
        await setup();
    });

    describe("Settings & Account Factory Deployment", () => {
        it("Test signers should have sUSD", async () => {
            const IERC20ABI = (
                await artifacts.readArtifact(
                    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
                )
            ).abi;
            sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);

            // account[0] balance
            let balance = await sUSD.balanceOf(accounts[0].address);
            expect(balance).to.equal(MINT_AMOUNT);

            // account[9] balance
            balance = await sUSD.balanceOf(accounts[9].address);
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

        /**
         * @notice `deployMarginBaseAccountForEOA()`
         *  - does the same thing but does not check ownership
         */
        it("Should deploy MarginBase contract and initialize it", async () => {
            const tx = await marginAccountFactory
                .connect(accounts[0])
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
                .connect(accounts[0])
                .marginAsset();
            expect(marginAsset).to.equal(SUSD_PROXY);
        });

        it("MarginBase owned by deployer", async () => {
            // check owner is deployer (i.e. account0)
            actualOwner = await marginAccount.connect(accounts[0]).owner();
            expect(owner).to.equal(actualOwner);
            expect(actualOwner).to.equal(accounts[0].address);
        });
    });

    describe("Deposit and Withdraw margin from account", () => {
        before("Setup", async () => {
            await deployMarginBaseAccountForEOA(accounts[1]);
        });

        it("Should Approve Allowance and Deposit Margin into Account", async () => {
            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[1])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // deposit sUSD into margin account
            await marginAccount.connect(accounts[1]).deposit(ACCOUNT_AMOUNT);

            // confirm deposit
            const balance = await sUSD.balanceOf(marginAccount.address);
            expect(balance).to.equal(ACCOUNT_AMOUNT);
        });

        it("Should Withdraw Margin from Account", async () => {
            const preBalance = await sUSD.balanceOf(accounts[1].address);

            // withdraw sUSD into margin account
            await marginAccount.connect(accounts[1]).withdraw(ACCOUNT_AMOUNT);

            // confirm withdraw
            const marginAccountBalance = await sUSD.balanceOf(
                marginAccount.address
            );
            expect(marginAccountBalance).to.equal(0);

            const postBalance = await sUSD.balanceOf(accounts[1].address);
            expect(preBalance).to.below(postBalance);
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

            it("Should open single position", async () => {
                await deployMarginBaseAccountForEOA(accounts[2]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[2])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[2])
                    .deposit(ACCOUNT_AMOUNT);

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
                    .connect(accounts[2])
                    .distributeMargin(newPosition);

                // confirm number of open internal positions that were defined above
                const numberOfInternalPositions = await marginAccount
                    .connect(accounts[2])
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
                    .connect(accounts[2])
                    .getPosition(MARKET_KEY_sETH);

                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(sizeDelta);
            });

            it("Should open multiple positions", async () => {
                await deployMarginBaseAccountForEOA(accounts[9]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[9])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[9])
                    .deposit(ACCOUNT_AMOUNT);

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
                    .connect(accounts[9])
                    .distributeMargin(newPositions);

                // confirm number of open internal positions that were defined above
                const numberOfInternalPositions = await marginAccount
                    .connect(accounts[9])
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
                    .connect(accounts[9])
                    .getPosition(MARKET_KEY_sUNI);

                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(uniSizeDelta);
            });
        });

        describe("Closing Positions", () => {
            it("Should close single position", async () => {
                await deployMarginBaseAccountForEOA(accounts[3]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[3])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[3])
                    .deposit(ACCOUNT_AMOUNT);

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
                    .connect(accounts[3])
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
                    .connect(accounts[3])
                    .distributeMargin(closingPosition);

                // confirm correct position details:
                // (1) market does not exist internally
                expect(
                    await marginAccount.getNumberOfInternalPositions()
                ).to.equal(0);

                // (2) size and margin
                const position = await marginAccount
                    .connect(accounts[3])
                    .getPosition(MARKET_KEY_sETH);

                expect(position.margin).to.equal(0);
                expect(position.size).to.equal(0);
            });

            it("Should close multiple positions", async () => {
                await deployMarginBaseAccountForEOA(accounts[10]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[10])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[10])
                    .deposit(ACCOUNT_AMOUNT);

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
                    .connect(accounts[10])
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
                    .connect(accounts[10])
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
                await deployMarginBaseAccountForEOA(accounts[11]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[11])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[11])
                    .deposit(ACCOUNT_AMOUNT);

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
                    .connect(accounts[11])
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
                    .connect(accounts[11])
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

            it("Should Modify Multiple Position's Size", async () => {
                await deployMarginBaseAccountForEOA(accounts[4]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[4])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[4])
                    .deposit(ACCOUNT_AMOUNT);

                // execute trades
                await marginAccount
                    .connect(accounts[4])
                    .distributeMargin(openingPositions);

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
                    .connect(accounts[4])
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(accounts[4])
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
                    .connect(accounts[4])
                    .getPosition(MARKET_KEY_sUNI);

                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(0);
                expect(position.size).to.equal(
                    uniSizeDelta.add(newUNISizeDelta)
                );
            });

            it("Should Modify Multiple Position's Margin (deposit)", async () => {
                await deployMarginBaseAccountForEOA(accounts[13]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[13])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[13])
                    .deposit(ACCOUNT_AMOUNT);

                // execute trades
                await marginAccount
                    .connect(accounts[13])
                    .distributeMargin(openingPositions);

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
                    .connect(accounts[13])
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(accounts[13])
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
                    .connect(accounts[4])
                    .getPosition(MARKET_KEY_sUNI);

                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.above(oldUNIposition.margin);
                expect(position.size).to.equal(uniSizeDelta);
            });

            it("Should Modify Multiple Position's Margin (withdraw)", async () => {
                await deployMarginBaseAccountForEOA(accounts[14]);

                // approve allowance for marginAccount to spend
                await sUSD
                    .connect(accounts[14])
                    .approve(marginAccount.address, ACCOUNT_AMOUNT);

                // deposit sUSD into margin account
                await marginAccount
                    .connect(accounts[14])
                    .deposit(ACCOUNT_AMOUNT);

                // execute trades
                await marginAccount
                    .connect(accounts[14])
                    .distributeMargin(openingPositions);

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
                    .connect(accounts[14])
                    .distributeMargin(newPositions);

                // confirm number of open positions
                const numberOfActivePositions = await marginAccount
                    .connect(accounts[14])
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
                    .connect(accounts[14])
                    .getPosition(MARKET_KEY_sUNI);

                // will not estimate exact value for margin
                // due to potential future fee changes (makes test brittle)
                expect(position.margin).to.be.below(oldUNIposition.margin);
                expect(position.size).to.equal(uniSizeDelta);
            });
        });
    });

    describe("Batch Tx", () => {
        before("Setup", async () => {
            await deployMarginBaseAccountForEOA(accounts[5]);
        });

        it("Should Deposit and open single position in one tx", async () => {
            const sizeDelta = ethers.BigNumber.from("500000000000000000");

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[5])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            const newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[5])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // confirm number of open internal positions that were defined above
            const numberOfInternalPositions = await marginAccount
                .connect(accounts[5])
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
                .connect(accounts[5])
                .getPosition(MARKET_KEY_sETH);
            // will not estimate exact value for margin
            // due to potential future fee changes (makes test brittle)
            expect(position.margin).to.be.above(0);
            expect(position.size).to.equal(sizeDelta);
        });
    });

    describe("Fees", () => {
        const sizeDelta = ethers.BigNumber.from("500000000000000000");

        it("Fee imposed when opening a position", async () => {
            await deployMarginBaseAccountForEOA(accounts[7]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[7])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            const newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // balance of treasury pre-trade
            const preBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[7])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // balance of treasury post-trade
            const postBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // get access to market
            const ethPerpMarket = await ethers.getContractAt(
                "IFuturesMarket",
                ETH_PERP_MARKET_ADDR
            );
            const assetPrice: { price: BigNumber; invalid: boolean } =
                await ethPerpMarket.assetPrice();

            // calculate fee
            let fee = sizeDelta.mul(tradeFee).div(MAX_BPS);
            // get fee in USD
            fee = fee.mul(assetPrice.price).div(ethers.utils.parseEther("1.0"));

            // confirm correct margin was trasnferred to Treasury
            expect(postBalance.sub(preBalance)).to.equal(fee);
        });

        it("Fee imposed when closing a position", async () => {
            await deployMarginBaseAccountForEOA(accounts[15]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[15])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position (open)
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[15])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // balance of treasury pre-trade
            const preBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // define new position (close)
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.Zero,
                    sizeDelta: sizeDelta.mul(-1),
                },
            ];

            await marginAccount
                .connect(accounts[15])
                .distributeMargin(newPosition);

            // balance of treasury post-trade
            const postBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // get access to market
            const ethPerpMarket = await ethers.getContractAt(
                "IFuturesMarket",
                ETH_PERP_MARKET_ADDR
            );
            const assetPrice: { price: BigNumber; invalid: boolean } =
                await ethPerpMarket.assetPrice();

            // calculate fee
            let fee = sizeDelta.mul(tradeFee).div(MAX_BPS);
            // get fee in USD
            fee = fee.mul(assetPrice.price).div(ethers.utils.parseEther("1.0"));

            // confirm correct margin was trasnferred to Treasury
            expect(postBalance.sub(preBalance)).to.equal(fee);
        });

        it("Event emits correct fee imposed when closing a position", async () => {
            await deployMarginBaseAccountForEOA(accounts[22]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[22])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position (open)
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[22])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // define new position (close)
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.Zero,
                    sizeDelta: sizeDelta.mul(-1),
                },
            ];

            // get access to market
            const ethPerpMarket = await ethers.getContractAt(
                "IFuturesMarket",
                ETH_PERP_MARKET_ADDR
            );
            const assetPrice: { price: BigNumber; invalid: boolean } =
                await ethPerpMarket.assetPrice();

            // calculate fee
            let fee = sizeDelta.mul(tradeFee).div(MAX_BPS);
            // get fee in USD
            fee = fee.mul(assetPrice.price).div(ethers.utils.parseEther("1.0"));

            const tx = await marginAccount
                .connect(accounts[22])
                .distributeMargin(newPosition);

            let receipt: ContractReceipt = await tx.wait();
            const event = receipt.events?.filter((x) => {
                return x.event == "FeeImposed";
            });
            const accountAddr = event![0].args![0];
            const feeImposedAmount = event![0].args![1];
            expect(accountAddr).to.equal(marginAccount.address);
            expect(feeImposedAmount).to.equal(fee);
        });

        /**
         * @notice checks correct fee when calling both:
         *          (1) depositAndModifyPositionForMarket
         *          (2) modifyPositionForMarketAndWithdraw
         */
        it("Fee imposed when modifying a position", async () => {
            await deployMarginBaseAccountForEOA(accounts[16]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[16])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position (open)
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[16])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // balance of treasury pre-trade
            const preBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // new size delta
            const newSizeDelta = sizeDelta.mul(2);

            // define new position (depositAndModifyPositionForMarket)
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.One,
                    sizeDelta: newSizeDelta,
                },
            ];

            await marginAccount
                .connect(accounts[16])
                .distributeMargin(newPosition);

            // balance of treasury post-trade
            const postBalance = await sUSD.balanceOf(KWENTA_TREASURY);

            // get access to market
            const ethPerpMarket = await ethers.getContractAt(
                "IFuturesMarket",
                ETH_PERP_MARKET_ADDR
            );
            const assetPrice: { price: BigNumber; invalid: boolean } =
                await ethPerpMarket.assetPrice();

            // calculate fee
            let fee = newSizeDelta.mul(tradeFee).div(MAX_BPS);
            // get fee in USD
            fee = fee.mul(assetPrice.price).div(ethers.utils.parseEther("1.0"));

            // confirm correct margin was trasnferred to Treasury
            expect(postBalance.sub(preBalance)).to.equal(fee);

            // balance of treasury pre-trade
            const preBalance2 = await sUSD.balanceOf(KWENTA_TREASURY);

            // define new position (modifyPositionForMarketAndWithdraw)
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.One.mul(-1),
                    sizeDelta: sizeDelta.mul(-1),
                },
            ];

            await marginAccount
                .connect(accounts[16])
                .distributeMargin(newPosition);

            // balance of treasury post-trade
            const postBalance2 = await sUSD.balanceOf(KWENTA_TREASURY);

            // calculate fee
            let fee2 = sizeDelta.mul(tradeFee).div(MAX_BPS);
            // get fee in USD
            fee2 = fee2
                .mul(assetPrice.price)
                .div(ethers.utils.parseEther("1.0"));

            // confirm correct margin was trasnferred to Treasury
            expect(postBalance2.sub(preBalance2)).to.equal(fee2);
        });

        /**
         * @dev if margin delta is x (where x > 0) and fee is y (where y > x)
         * then margin will be withdrawn from position despite
         * depositAndModifyPositionForMarket() being called
         */
        it("Fee still imposed when larger than margin deposited", async () => {
            await deployMarginBaseAccountForEOA(accounts[17]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[17])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[17])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            // set trade fee to be 10% of sizeDelta
            const newTradeFee = 100;
            await marginBaseSettings
                .connect(accounts[0])
                .setTradeFee(newTradeFee);

            /**
             * @dev fee is 1% and sizeDelta below is 1 ether (i.e. ~2_000 USD)
             * therefore, fee should be 20 USD.
             * There is only 1_000 USD in the market and trade will deposit
             * 1 USD (i.e. margin delta), thus margin must be pulled from
             * market for fee to be imposed
             */
            const newMarginDelta = TEST_VALUE.div(1000); // 1 USD
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: newMarginDelta,
                    sizeDelta: sizeDelta.mul(2),
                },
            ];

            // position in eth perp market pre-trade
            const preTradeMarketPos = await marginAccount.getPosition(
                MARKET_KEY_sETH
            );

            // trade
            await marginAccount
                .connect(accounts[17])
                .distributeMargin(newPosition);

            // position in eth perp market post-trade
            const postTradeMarketPos = await marginAccount.getPosition(
                MARKET_KEY_sETH
            );

            /**
             * @notice confirm fee pulled from market
             * @dev since our fee was 10%, we assume margin decrease in market
             * is at least that much
             */

            // get access to market
            const ethPerpMarket = await ethers.getContractAt(
                "IFuturesMarket",
                ETH_PERP_MARKET_ADDR
            );
            const assetPrice: { price: BigNumber; invalid: boolean } =
                await ethPerpMarket.assetPrice();

            // calculate fee
            let fee = sizeDelta.mul(newTradeFee).div(MAX_BPS);
            // get fee in USD
            fee = fee.mul(assetPrice.price).div(ethers.utils.parseEther("1.0"));
            expect(fee).to.be.below(
                preTradeMarketPos.margin.sub(postTradeMarketPos.margin)
            );
        });

        /**
         * @dev if margin in market is x (where x > 0) and fee is y (where y >= x)
         * then trade will fail due to insufficient margin
         */
        it("Trade fails if fee is greater than margin in Market", async () => {
            await deployMarginBaseAccountForEOA(accounts[18]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[18])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[18])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            /**
             * @notice at this point, total margin in market is TEST_VALUE
             */

            // set trade fee to be 90% of sizeDelta
            await marginBaseSettings.connect(accounts[0]).setTradeFee(9_000);

            /**
             * @dev fee is 90% and sizeDelta below is 1 ether (i.e. ~2_000 USD)
             * therefore, fee should be 1_800 USD.
             * There is only 1_000 USD in the market, thus trade should fail
             */
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.Zero,
                    sizeDelta: sizeDelta.mul(2),
                },
            ];

            // trade
            const tx = marginAccount
                .connect(accounts[18])
                .distributeMargin(newPosition);
            await expect(tx).to.be.revertedWith("Insufficient margin");
        });

        /**
         * @dev if margin in market is x (where x > 0) and fee is y
         * then trade will fail if y being imposed results in
         * leverage based on x being greater than what is allowed (10x at this block)
         * @notice if margin delta is non-zero, we expect modifyPosition to be called thus
         * error "Max leverage exceeded" to be thrown
         */
        it("Trade fails if fee greater than max leverage with non-zero margin delta", async () => {
            await deployMarginBaseAccountForEOA(accounts[19]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[19])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[19])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            /**
             * @notice at this point, total margin in market is TEST_VALUE
             */

            // set trade fee to be 40% of sizeDelta
            await marginBaseSettings.connect(accounts[0]).setTradeFee(4_000);

            const newMarginDelta = TEST_VALUE.sub(TEST_VALUE.div(10));
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: newMarginDelta,
                    sizeDelta: sizeDelta.mul(2),
                },
            ];

            // trade
            const tx = marginAccount
                .connect(accounts[19])
                .distributeMargin(newPosition);
            await expect(tx).to.be.revertedWith("Max leverage exceeded");
        });

        /**
         * @dev if margin in market is x (where x > 0) and fee is y
         * then trade will fail if y being imposed results in
         * leverage based on x being greater than what is allowed (10x at this block)
         * @notice if margin delta is zero, we do not expect modifyPosition() to be called
         * and only transfeMargin() thus we expect error "Insufficient margin" to be
         * thrown despite it being a max leverage exceeded issue
         */
        it("Trade fails if fee greater than max leverage with zero margin delta", async () => {
            await deployMarginBaseAccountForEOA(accounts[20]);

            // set trade fee to be 0% of sizeDelta
            await marginBaseSettings.connect(accounts[0]).setTradeFee(0);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[20])
                .approve(marginAccount.address, ACCOUNT_AMOUNT);

            // define new position
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: TEST_VALUE,
                    sizeDelta: sizeDelta,
                },
            ];

            // deposit margin into account and execute trade
            await marginAccount
                .connect(accounts[20])
                .depositAndDistribute(ACCOUNT_AMOUNT, newPosition);

            /**
             * @notice at this point, total margin in market is TEST_VALUE
             */

            // set trade fee to be 40% of sizeDelta
            await marginBaseSettings.connect(accounts[0]).setTradeFee(4_000);

            /**
             * @dev fee is 40% and sizeDelta below is 1 ether (i.e. ~2_000 USD)
             * therefore, fee should be 800 USD.
             * There is only 1_000 USD in the market, thus trade results
             * in 200 USD remaining.
             * This exceeds max leverage based on size and
             * margin in market and thus should fail with Max leverage exceeded
             * @dev synthetix adds their fee which pushes us past 10x
             */
            newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: ethers.constants.Zero,
                    sizeDelta: sizeDelta.mul(2),
                },
            ];

            // trade
            const tx = marginAccount
                .connect(accounts[20])
                .distributeMargin(newPosition);
            await expect(tx).to.be.revertedWith("Insufficient margin");
        });

        it("Trade fails if trade fee exceeds free margin", async () => {
            await deployMarginBaseAccountForEOA(accounts[21]);

            // approve allowance for marginAccount to spend
            await sUSD
                .connect(accounts[21])
                .approve(marginAccount.address, MINT_AMOUNT);

            // set trade fee to be 10% of sizeDelta
            await marginBaseSettings.connect(accounts[0]).setTradeFee(1_000);

            /**
             * @notice define new positions which attempt to spend margin
             * set aside for fee resulting inadequate margin to pay fee
             *
             * @dev margin delta in second position transfers
             * remaining MINT_AMOUNT plus fee (i.e. sizeDelta / 10)
             * from first position which results in no margin left to pay
             * trade fees at the end of the tx
             */
            let newPosition = [
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: MINT_AMOUNT.div(2),
                    sizeDelta: sizeDelta, // 1_000 USD
                },
                {
                    marketKey: MARKET_KEY_sETH,
                    marginDelta: MINT_AMOUNT.div(2).add(sizeDelta.div(10)),
                    sizeDelta: sizeDelta, // 1_000 USD
                },
            ];

            // deposit margin into account and execute trade
            const tx = marginAccount
                .connect(accounts[21])
                .depositAndDistribute(MINT_AMOUNT, newPosition);

            await expect(tx).to.revertedWith("CannotPayFee");
        });
    });
});
