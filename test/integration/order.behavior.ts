/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { Contract } from "ethers";
import { mintToAccountSUSD } from "../utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
    setBalance,
    impersonateAccount,
} from "@nomicfoundation/hardhat-network-helpers";
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
let addressResolver;

// synthetix: proxy
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";
let sUSD: Contract;

//const EXCHANGER = // We now get this a runtime depending on fork block
let exchanger: Contract;

// synthetix: market keys
// see: https://github.com/Synthetixio/synthetix/blob/develop/publish/deployed/mainnet-ovm/futures-markets.json
const BYTES32_sUSD = ethers.utils.formatBytes32String("sUSD");
const MARKET_KEY_sETH = ethers.utils.formatBytes32String("sETH");

// gelato
const GELATO_OPS = "0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c";
const GELATO_ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

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

    const IERC20ABI = (
        await artifacts.readArtifact(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
        )
    ).abi;
    sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);

    const ADDRESS_RESOLVER_ABI = (
        await artifacts.readArtifact("IAddressResolver")
    ).abi;
    addressResolver = new ethers.Contract(
        ADDRESS_RESOLVER,
        ADDRESS_RESOLVER_ABI,
        waffle.provider
    );
    const exchangerAddress = await addressResolver.requireAndGetAddress(
        ethers.utils.formatBytes32String("Exchanger"),
        ""
    );

    const EXCHANGER_ABI = (await artifacts.readArtifact("IExchanger")).abi;
    exchanger = new ethers.Contract(
        exchangerAddress,
        EXCHANGER_ABI,
        waffle.provider
    );
};

/*///////////////////////////////////////////////////////////////
                                TESTS
///////////////////////////////////////////////////////////////*/

describe("Integration: Test Advanced Orders", () => {
    describe("Test integration w/ Gelato", () => {
        const sizeDelta = ethers.BigNumber.from("500000000000000000");
        let gelatoOps: Contract;
        before("Fork Network", async () => {
            await forkAtBlock(9000000);
            const OPS_ABI = (await artifacts.readArtifact("IOps")).abi;
            gelatoOps = new ethers.Contract(
                GELATO_OPS,
                OPS_ABI,
                waffle.provider
            );
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

            await setBalance(marginAccount.address, 10 ** 18);
        });

        it("Place order w/ gelato", async () => {
            // submit order to gelato
            await marginAccount
                .connect(account0)
                .placeOrder(MARKET_KEY_sETH, TEST_VALUE, sizeDelta, 0, 0);

            // confirm order placed
            const order = await marginAccount.orders(0);
            expect(order.marketKey).to.equal(MARKET_KEY_sETH);
        });

        it("Cancel order through gelato", async () => {
            // submit order to gelato
            await marginAccount
                .connect(account0)
                .placeOrder(MARKET_KEY_sETH, TEST_VALUE, sizeDelta, 0, 0);

            // attempt to cancel order
            const order = await marginAccount.orders(0);
            await expect(marginAccount.connect(account0).cancelOrder(0))
                .to.emit(gelatoOps, "TaskCancelled")
                .withArgs(order.gelatoTaskId, marginAccount.address);
        });

        describe("Execute order (as Gelato)", () => {
            const gelatoFee = 100;
            const currentPrice = "1961800000000000000000"; // current ETH price at forked block

            const executeOrder = async () => {
                const order = await marginAccount.orders(0);
                const gelato = await marginAccount.gelato();
                const checkerCalldata =
                    marginAccount.interface.encodeFunctionData("checker", [0]);
                const executeOrderCalldata =
                    marginAccount.interface.encodeFunctionData("executeOrder", [
                        0,
                    ]);
                const resolverHash = await gelatoOps.getResolverHash(
                    marginAccount.address,
                    checkerCalldata
                );

                // execute order as Gelato would
                await impersonateAccount(gelato);
                const tx = gelatoOps
                    .connect(await ethers.getSigner(gelato))
                    .exec(
                        gelatoFee,
                        GELATO_ETH,
                        marginAccount.address,
                        false,
                        true, // reverts for off-chain sim
                        resolverHash,
                        marginAccount.address,
                        executeOrderCalldata
                    );

                return {
                    tx,
                    order,
                    executeOrderCalldata,
                };
            };

            beforeEach("Place order", async () => {
                // submit order to gelato
                await marginAccount
                    .connect(account0)
                    .placeOrder(
                        MARKET_KEY_sETH,
                        TEST_VALUE,
                        sizeDelta,
                        ethers.constants.MaxUint256,
                        0
                    );
            });

            it("ExecSuccess emitted from gelato", async () => {
                const { tx, order, executeOrderCalldata } =
                    await executeOrder();

                await expect(tx)
                    .to.emit(gelatoOps, "ExecSuccess")
                    .withArgs(
                        gelatoFee,
                        GELATO_ETH,
                        marginAccount.address,
                        executeOrderCalldata,
                        order.gelatoTaskId,
                        true
                    );
            });

            it("Gelato task unregistered", async () => {
                const gelatoTaskId = (await marginAccount.orders(0))
                    .gelatoTaskId;

                // Expect task to be registered
                expect(await gelatoOps.taskCreator(gelatoTaskId)).to.be.equal(
                    marginAccount.address
                );

                const { tx } = await executeOrder();
                await tx;

                // Expect that we cancel the task for gelato after execution
                expect(await gelatoOps.taskCreator(gelatoTaskId)).to.be.equal(
                    ethers.constants.AddressZero
                );
            });

            it("OrderFilled emitted", async () => {
                const { tx } = await executeOrder();

                await expect(tx)
                    .to.emit(marginAccount, "OrderFilled")
                    .withArgs(
                        marginAccount.address,
                        0,
                        currentPrice,
                        gelatoFee
                    );
            });

            it("Order 'book' cleared", async () => {
                const { tx } = await executeOrder();
                await tx;

                expect(
                    (await marginAccount.orders(0)).gelatoTaskId
                ).to.be.equal(ethers.constants.HashZero);
            });

            it("Fee transfer is correct", async () => {
                const oldTreasuryPrice = await sUSD.balanceOf(KWENTA_TREASURY);

                const { tx } = await executeOrder();
                await tx;

                const expectedFee = sizeDelta
                    .mul(currentPrice)
                    .div(ethers.constants.WeiPerEther)
                    .mul(limitOrderFee + tradeFee)
                    .div(10000);
                expect(await sUSD.balanceOf(KWENTA_TREASURY)).to.equal(
                    oldTreasuryPrice.add(expectedFee)
                );
            });
        });
    });

    describe("Test fee integration w/ Synthetix", () => {
        const sizeDelta = ethers.BigNumber.from("500000000000000000");

        it("Dynamic fee is 0", async () => {
            // setup
            await forkAtBlock(9000000);
            await setup();
            await deployMarginBaseAccountForEOA(account0);
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, ACCOUNT_AMOUNT);
            await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);
            await setBalance(marginAccount.address, 10 ** 18);

            // submit order to gelato
            await marginAccount.connect(account0).placeOrderWithFeeCap(
                MARKET_KEY_sETH,
                TEST_VALUE,
                sizeDelta,
                ethers.constants.MaxUint256, // target price
                0,
                10
            );

            // will allow execution
            const [isValid] = await marginAccount.validOrder(0);
            expect(isValid).to.equal(true);
        });

        it("Dynamic fee above specified cap", async () => {
            // setup
            await forkAtBlock(9002000); // 0.002194139527461657 or 21.9 BP dynamic fee
            await setup();
            await deployMarginBaseAccountForEOA(account0);
            await sUSD
                .connect(account0)
                .approve(marginAccount.address, ACCOUNT_AMOUNT);
            await marginAccount.connect(account0).deposit(ACCOUNT_AMOUNT);
            await setBalance(marginAccount.address, 10 ** 18);

            const feeCap = ethers.utils.parseEther("20").div(MAX_BPS);

            // submit order to gelato
            await marginAccount.connect(account0).placeOrderWithFeeCap(
                MARKET_KEY_sETH,
                TEST_VALUE,
                sizeDelta,
                ethers.constants.MaxUint256, // target price
                0,
                feeCap
            );

            // will not allow execution
            const [isValid] = await marginAccount.validOrder(0);
            expect(isValid).to.equal(false);
        });
    });
});
