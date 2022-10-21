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
    const version = "1.0.2";
    const marginAsset = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9"; // ProxyERC20sUSD on OE Mainnet
    const addressResolver = "0x1Cb059b7e74fD21665968C908806143E744D5F30"; // ReadProxyAddressResolver on OE Mainnet
    const marginBaseSettings = await deployments.get("MarginBaseSettings"); // Settings on OE Mainnet
    const ops = "0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c"; // Ops on OE Mainnet

    await deploy("MarginAccountFactory", {
        from: deployer,
        args: [version, marginAsset, addressResolver, marginBaseSettings.address, ops],
        log: true,
    });
};

export default deployMarginAccountFactory;

deployMarginAccountFactory.tags = ["MarginAccountFactory"];

// this ensure the MarginBaseSettings script is executed first, so `deployments.get('MarginBaseSettings')` succeeds
deployMarginAccountFactory.dependencies = ["MarginBaseSettings"];
