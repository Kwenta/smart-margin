// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMarginAccountFactoryStorage.sol";

/// @title Kwenta MarginBase Factory Storage
/// @author JaredBorders (jaredborders@pm.me)
/// @notice Store for persistent account data
contract MarginAccountFactoryStorage is IMarginAccountFactoryStorage, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // @TODO DOCS
    mapping(address => address) public deployedMarginAccounts;
    
    // @TODO DOCS
    mapping(address => bool) public verifiedFactories;

    /*//////////////////////////////////////////////////////////////
                              FACTORY AUTH
    //////////////////////////////////////////////////////////////*/

    // @TODO DOCS
    error FactoryOnly();

    // @TODO DOCS
    modifier onlyFactory() {
        if (!verifiedFactories[msg.sender]) {
            revert FactoryOnly();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // @TODO DOCS
    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    // @TODO DOCS
    function addDeployedAccount(address _creator, address _account)
        external
        onlyFactory
    {
        deployedMarginAccounts[_creator] = _account;
    }

    // @TODO DOCS
    function addVerifiedFactory(address _factory) external onlyOwner {
        verifiedFactories[_factory] = true;
    }
}
