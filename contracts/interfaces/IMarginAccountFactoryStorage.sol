// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title Kwenta MarginAccountFactoryStorage Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginAccountFactoryStorage {
    function addDeployedAccount(address _creator, address _account) external;

    function addVerifiedFactory(address _factory) external;

    function deployedMarginAccounts(address) external view returns (address);

    function verifiedFactories(address) external view returns (bool);
}
