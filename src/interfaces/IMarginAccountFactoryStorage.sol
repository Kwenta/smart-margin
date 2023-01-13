// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title Kwenta MarginAccountFactoryStorage Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginAccountFactoryStorage {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown if non-verified factory is the function caller
    error FactoryOnly();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice pass creator address and returns MarginBase account address
    /// @param _creator: address of creator (i.e. factory caller)
    /// @return address of MarginBase account
    function deployedMarginAccounts(address _creator)
        external
        view
        returns (address);

    /// @notice pass factory address and returns true if it is verified 
    /// (i.e. can create Kwenta MarginBase accounts)
    /// @param _factory: address of factory
    /// @return bool representing if factory is verified
    function verifiedFactories(address _factory) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice update store to track new account
    /// @dev can only be called by verified factory
    /// @param _creator: address which created margin account
    /// @param _account: address of newly created margin account
    function addDeployedAccount(address _creator, address _account) external;

    /// @notice update store to track new verified factory
    /// @dev can only be called by the owner
    /// @param _factory: address of factory
    function addVerifiedFactory(address _factory) external;
}
