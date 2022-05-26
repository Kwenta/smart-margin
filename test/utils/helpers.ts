import { BigNumber } from "@ethersproject/bignumber";
import { artifacts, ethers, network } from "hardhat";

/*
 * mint sUSD and transfer to account address specified:
 *
 * Issuer.sol is an auxiliary helper contract that performs the issuing and burning functionality.
 * Synth.sol is the base ERC20 token contract comprising most of the behaviour of all synths.
 *
 * Issuer is considered an "internal contract" therefore, it is permitted to call
 * Synth.issue() which is restricted by the onlyInternalContracts modifier. Synth.issue()
 * updates the token state (i.e. balance and total existing tokens) which effectively
 * can be used to "mint" an account the underlying synth.
 *
 * @param accountAddress: address to mint sUSD for
 * @param amount: amount to mint
 */

export const mintToAccountSUSD = async (
    accountAddress: string,
    amount: BigNumber
) => {
    // internal contract which can call synth.issue()
    const issuerAddress = "0x939313420A85ab8F21B8c2fE15b60528f34E0d63";
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [issuerAddress],
    });
    const issuerSigner = await ethers.getSigner(issuerAddress);

    // contract needs ETH to send tx
    await network.provider.send("hardhat_setBalance", [
        issuerAddress,
        "0x38d7ea4c68000", // 0.001 ETH
    ]);

    // MultiCollateralSynth contract address for sUSD
    const synthSUSDAddress = "0xD1599E478cC818AFa42A4839a6C665D9279C3E50";
    const ISynthABI = (
        await artifacts.readArtifact("contracts/interfaces/ISynth.sol:ISynth")
    ).abi;
    const synth = new ethers.Contract(synthSUSDAddress, ISynthABI);

    // "mint" accountAddress specified amount of sUSD
    await synth.connect(issuerSigner).issue(accountAddress, amount);
};
