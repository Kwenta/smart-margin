// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMarginAccountFactoryStorage.sol";

/// @title Kwenta MarginBase Factory Storage
/// @author JaredBorders (jaredborders@pm.me)
/// @notice Store for persistent account data
contract MarginAccountFactoryStorage is IMarginAccountFactoryStorage, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice map of addresses which created a margin account
    mapping(address => address) public deployedMarginAccounts;

    /// @notice map of factories which are verified to create margin accounts
    /// @dev only can be updated by the owner
    mapping(address => bool) public verifiedFactories;

    /*//////////////////////////////////////////////////////////////
                              FACTORY AUTH
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown if non-verified factory is the function caller
    error FactoryOnly();

    /// @notice ensure caller is a verified factory
    modifier onlyFactory() {
        if (!verifiedFactories[msg.sender]) {
            revert FactoryOnly();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice sets owner of store
    /// @param _owner: address of owner; originally deployer but
    /// will be changed to this param
    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice update store to track new account
    /// @dev can only be called by verified factory
    /// @param _creator: address which created margin account
    /// @param _account: address of newly created margin account
    function addDeployedAccount(address _creator, address _account)
        external
        onlyFactory
    {
        deployedMarginAccounts[_creator] = _account;
    }

    /// @notice update store to track new verified factory
    /// @dev can only be called by the owner
    /// @param _factory: address of factory
    function addVerifiedFactory(address _factory) external onlyOwner {
        verifiedFactories[_factory] = true;
    }
}
