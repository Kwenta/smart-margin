/* eslint-disable no-unused-expressions */
import { expect } from 'chai';
import { artifacts, ethers, network, waffle } from 'hardhat';
import { Contract } from 'ethers';
import { mintToAccountSUSD } from '../utils/helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import dotenv from 'dotenv';

dotenv.config();

// constants
const TEST_VALUE = ethers.BigNumber.from('1000000000000000000');
const TREASURY_DAO = '0x82d2242257115351899894eF384f779b5ba8c695';

// synthetix
const ADDRESS_RESOLVER = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';
// synthetix: proxy
const SUSD_PROXY = '0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9';
// synthetix: market keys

// cross margin
let marginAccountFactory: Contract;
let marginBase: Contract;

// test accounts
let account0: SignerWithAddress;
let account1: SignerWithAddress;
let account2: SignerWithAddress;

const forkAtBlock = async (block: number) => {
    await network.provider.request({
        method: 'hardhat_reset',
        params: [
            {
                forking: {
                    jsonRpcUrl: process.env.ARCHIVE_NODE_URL_L2,
                    blockNumber: block, // 8626683
                },
            },
        ],
    });
};

describe('Integration: Test Cross Margin', () => {

    before('Fork and Mint sUSD to Test Account', async () => {
        [account0, account1, account2] = await ethers.getSigners();

		await forkAtBlock(9000000);
        await mintToAccountSUSD(account0.address, TEST_VALUE);

        const IERC20ABI = (await artifacts.readArtifact("contracts/interfaces/IERC20.sol:IERC20")).abi;
        const sUSD = new ethers.Contract(SUSD_PROXY, IERC20ABI, waffle.provider);
        const balance = await sUSD.balanceOf(account0.address);
        expect(balance).to.equal(TEST_VALUE);
	});

    it('Test MarginAccountFactory deployment', async () => {
        const MarginAccountFactory = await ethers.getContractFactory(
            'MarginAccountFactory'
        );
        marginAccountFactory = await MarginAccountFactory.deploy(
            '1.0.0',
            SUSD_PROXY,
            ADDRESS_RESOLVER
        );
        await marginAccountFactory.deployed();
        expect(marginAccountFactory.address).to.exist;
    });

    it('Test MarginBase deployment', async () => {
        const marginBaseAddress = await marginAccountFactory.connect(account0).newAccount();
        marginBase = await ethers.getContractAt(
            'MarginBase',
            marginBaseAddress
        );
        expect(marginBase.address).to.exist;
    });
});
