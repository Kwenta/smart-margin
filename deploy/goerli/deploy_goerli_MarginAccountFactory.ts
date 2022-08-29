import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                TEST DEPLOYMENT ON OPTIMISTIC GOERLI
///////////////////////////////////////////////////////////////*/

const deployMarginAccountFactoryOnGoerli: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const version = "1.0.0";
    const marginAsset = "0xeBaEAAD9236615542844adC5c149F86C36aD1136"; // ProxyERC20sUSD on Goerli
    const addressResolver = "0x9Fc84992dF5496797784374B810E04238728743d"; // ReadProxyAddressResolver on Goerli
    const marginBaseSettings = await deployments.get("MarginBaseSettings"); // Settings on Goerli
    const ops = "0x255F82563b5973264e89526345EcEa766DB3baB2"; // Ops on Goerli

    await deploy("MarginAccountFactory", {
        from: deployer,
        args: [version, marginAsset, addressResolver, marginBaseSettings.address, ops],
        log: true,
    });
};
export default deployMarginAccountFactoryOnGoerli;
deployMarginAccountFactoryOnGoerli.tags = ["MarginAccountFactory-Goerli"];
// this ensure the MarginBaseSettings-Goerli script is executed first, so `deployments.get('MarginBaseSettings')` succeeds
deployMarginAccountFactoryOnGoerli.dependencies = ["MarginBaseSettings-Goerli"];
