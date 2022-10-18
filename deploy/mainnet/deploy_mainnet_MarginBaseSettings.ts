import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                MAINNET DEPLOYMENT ON OPTIMISM
///////////////////////////////////////////////////////////////*/

const deployMarginBaseSettings: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const treasury = "0x82d2242257115351899894eF384f779b5ba8c695"; // Kwenta Treasury on OE
    const distributionFee = 2; // BPS
    const limitOrderFee = 3; // BPS
    const stopLossFee = 3; // BPS

    await deploy("MarginBaseSettings", {
        from: deployer,
        args: [treasury, distributionFee, limitOrderFee, stopLossFee],
        log: true,
    });
};
export default deployMarginBaseSettings;
deployMarginBaseSettings.tags = ["MarginBaseSettings"];
