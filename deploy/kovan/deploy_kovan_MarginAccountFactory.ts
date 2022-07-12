import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                TEST DEPLOYMENT ON OPTIMISTIC KOVAN
///////////////////////////////////////////////////////////////*/

const deployMarginAccountFactoryOnKovan: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const version = "1.0.0";
    const marginAsset = "0xaA5068dC2B3AADE533d3e52C6eeaadC6a8154c57"; // ProxyERC20sUSD on Kovan
    const addressResolver = "0xb08b62e1cdfd37eCCd69A9ACe67322CCF801b3A6"; // AddressResolver on Kovan
    const marginBaseSettings = await deployments.get("MarginBaseSettings"); // Settings on Kovan
    const ops = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F"; // Ops on Kovan

    await deploy("MarginAccountFactory", {
        from: deployer,
        args: [version, marginAsset, addressResolver, marginBaseSettings.address, ops],
        log: true,
    });
};

export default deployMarginAccountFactoryOnKovan;

deployMarginAccountFactoryOnKovan.tags = ["MarginAccountFactory-Kovan"];

// this ensure the MarginBaseSettings-Kovan script is executed first, so `deployments.get('MarginBaseSettings')` succeeds
deployMarginAccountFactoryOnKovan.dependencies = ["MarginBaseSettings-Kovan"];
