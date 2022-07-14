import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

/*///////////////////////////////////////////////////////////////
                MAINNET DEPLOYMENT ON OPTIMISM
///////////////////////////////////////////////////////////////*/

const deployMarginAccountFactory: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    // constructor params
    const version = "1.0.0";
    const marginAsset = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9"; // ProxyERC20sUSD on OE Mainnet
    const addressResolver = "0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C"; // AddressResolver on OE Mainnet
    const marginBaseSettings = await deployments.get("MarginBaseSettings"); // Settings on OE Mainnet
    const ops = "0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c"; // Ops on OE Mainnet

    await deploy("MarginAccountFactory", {
        from: deployer,
        args: [version, marginAsset, addressResolver, marginBaseSettings, ops],
        log: true,
    });
};

export default deployMarginAccountFactory;

deployMarginAccountFactory.tags = ["MarginAccountFactory"];

// this ensure the MarginBaseSettings script is executed first, so `deployments.get('MarginBaseSettings')` succeeds
deployMarginAccountFactory.dependencies = ["MarginBaseSettings"];
