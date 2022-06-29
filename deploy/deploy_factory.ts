import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

// constructor variables: Mainnet OE network
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";
const ADDRESS_RESOLVER = "0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy } = hre.deployments;
    const { deployer } = await hre.getNamedAccounts();
    console.log("deployer", deployer)
    await deploy("MarginAccountFactory", {
        from: deployer,
        args: [
            "1.0.0", SUSD_PROXY, ADDRESS_RESOLVER
        ],
        log: true,
    });
};
export default func;
module.exports.tags = ["MarginAccountFactory"];
