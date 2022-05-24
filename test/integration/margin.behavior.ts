/* eslint-disable no-unused-expressions */
import { expect } from 'chai';
import { ethers, artifacts, waffle, network } from 'hardhat';
import dotenv from 'dotenv';
import { Contract } from 'ethers';

dotenv.config();

// constants
const TEST_ADDRESS_0 = '0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c'; // EOA
// const TEST_ADDRESS_1 = '0xB483F21dC981D2D1E483192a15FcAc281669bF73'; // EOA
// const TEST_VALUE = ethers.BigNumber.from('10000000000000000');
// const TREASURY_DAO = '0x82d2242257115351899894eF384f779b5ba8c695'; // actual address

// synthetix
const ADDRESS_RESOLVER = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';
// synthetix: proxy
const SUSD_PROXY = '0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9';
// synthetix: market keys

// cross margin
let marginAccountFactory: Contract;
let marginBase: Contract;

const forkAndImpersonateAtBlock = async (block: number, account: string) => {
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

    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [account],
    });
};

describe('Integration: Test Cross Margin', function () {
    forkAndImpersonateAtBlock(6950543, TEST_ADDRESS_0);

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
        const signer = await ethers.getSigner(TEST_ADDRESS_0);
        const marginBaseAddress = await marginAccountFactory
            .connect(signer)
            .newAccount();
        marginBase = await ethers.getContractAt(
            'MarginBase',
            marginBaseAddress,
            signer
        );
        expect(marginBase.address).to.exist;
    });
});
