import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                TEST DEPLOYMENT ON OPTIMISTIC KOVAN
///////////////////////////////////////////////////////////////*/

const deployMarginBaseSettingsOnKovan: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const treasury = "0xB594a842A528cb8b80536a84D3DfEd73C2c0c658"; // EOA on Kovan
    const distributionFee = 5; // BPS
    const limitOrderFee = 5; // BPS
    const stopLossFee = 5; // BPS

    await deploy("MarginBaseSettings", {
        from: deployer,
        args: [treasury, distributionFee, limitOrderFee, stopLossFee],
        log: true,
    });
};
export default deployMarginBaseSettingsOnKovan;
deployMarginBaseSettingsOnKovan.tags = ["MarginBaseSettings-Kovan"];
