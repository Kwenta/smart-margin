import hre, { ethers } from "hardhat";
import { Contract } from "ethers";

// synthetix
const ADDRESS_RESOLVER = "0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C";
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";

// cross margin
let marginAccountFactory: Contract;
let marginAccount: Contract;

async function main() {
    const [deployer] = await ethers.getSigners();

    // ========== DEPLOYMENT ========== */
    console.log("\nBeginning deployments...");
    deployFactory();
}

async function deployFactory() {
    // deploy
    marginAccountFactory = await (
        await ethers.getContractFactory("MarginAccountFactory")
    ).deploy("1.0.0", SUSD_PROXY, ADDRESS_RESOLVER);

    // save deployment
    await saveDeployments("MarginAccountFactory", marginAccountFactory);
    
    // log address
    console.log(
        "\n✅ Deployed MarginAccountFactory at address: " +
            marginAccountFactory.address + "\n"
    );
}

async function saveDeployments(name: string, contract: Contract) {
    // For hardhat-deploy plugin to save deployment artifacts
    const { deployments } = hre;
    const { save } = deployments;

    const artifact = await deployments.getExtendedArtifact(name);
    let deployment = {
        address: contract.address,
        ...artifact,
    };

    await save(name, deployment);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
