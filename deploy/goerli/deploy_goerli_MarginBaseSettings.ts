import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                TEST DEPLOYMENT ON OPTIMISTIC GOERLI
///////////////////////////////////////////////////////////////*/

const deployMarginBaseSettingsOnGoerli: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const treasury = "0x6e1768574dC439aE6ffCd2b0A0f218105f2612c6"; // EOA on Goerli
    const distributionFee = 5;  // BPS
    const limitOrderFee = 5;    // BPS
    const stopLossFee = 5;      // BPS

    await deploy("MarginBaseSettings", {
        from: deployer,
        args: [treasury, distributionFee, limitOrderFee, stopLossFee],
        log: true,
    });
};
export default deployMarginBaseSettingsOnGoerli;
deployMarginBaseSettingsOnGoerli.tags = ["MarginBaseSettings-Goerli"];