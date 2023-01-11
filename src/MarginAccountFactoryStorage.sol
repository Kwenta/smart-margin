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
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

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

    /// @inheritdoc IMarginAccountFactoryStorage
    function addDeployedAccount(address _creator, address _account)
        external
        override
        onlyFactory
    {
        deployedMarginAccounts[_creator] = _account;
    }

    /// @inheritdoc IMarginAccountFactoryStorage
    function addVerifiedFactory(address _factory) external override onlyOwner {
        verifiedFactories[_factory] = true;
    }
}
