// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IFactory} from "./IFactory.sol";

/// @title Kwenta Factory Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when new account is created
    /// @param creator: account creator (address that called newAccount())
    /// @param account: address of account that was created (will be address of proxy)
    event NewAccount(
        address indexed creator,
        address indexed account,
        bytes32 version
    );

    /// @notice emitted when system is upgraded
    /// @param implementation: address of new implementation
    /// @param settings: address of new settings
    /// @param marginAsset: address of new margin asset
    /// @param addressResolver: new synthetix address resolver
    /// @param ops: new gelato ops -- must be payable
    event SystemUpgraded(
        address implementation,
        address settings,
        address marginAsset,
        address addressResolver,
        address ops
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when newAccount() is called
    /// by an address which has already made an account
    /// @param account: address of account previously created
    error AlreadyCreatedAccount(address account);

    /// @notice thrown when Account creation fails
    /// @param data: data returned from failed low-level call
    error AccountCreationFailed(bytes data);

    /// @notice thrown when factory is not upgradable
    error CannotUpgrade();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @return canUpgrade: bool to determine if factory can be upgraded
    function canUpgrade() external view returns (bool);

    /// @return logic: account logic address
    function implementation() external view returns (address);

    /// @return settings: address of settings for accounts
    function settings() external view returns (address);

    /// @return marginAsset: address of ERC20 token used to interact with markets
    function marginAsset() external view returns (address);

    /// @return addressResolver: address of synthetix address resolver
    function addressResolver() external view returns (address);

    /// @return ops: payable contract address for gelato ops
    function ops() external view returns (address payable);

    /// @return accountAddress: address of account created by creator
    function creatorToAccount(address) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice create unique account proxy for function caller
    /// @return accountAddress address of account created
    function newAccount() external returns (address payable accountAddress);

    /// @notice upgrade system (implementation, settings, marginAsset, addressResolver, ops)
    /// @dev *DANGER* this function does not check any of the parameters for validity,
    /// thus, a bad upgrade could result in severe consequences. 
    /// @param _implementation: address of new implementation
    /// @param _settings: address of new settings
    /// @param _marginAsset: address of new margin asset
    /// @param _addressResolver: new synthetix address resolver
    /// @param _ops: new gelato ops
    function upgradeSystem(
        address payable _implementation,
        address _settings,
        address _marginAsset,
        address _addressResolver,
        address payable _ops
    ) external;
}
