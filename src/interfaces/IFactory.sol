// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

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
    error OnlyOneAccountPerAddress(address account);

    /// @notice thrown when Account creation fails at initialization step
    /// @param data: data returned from failed low-level call
    error AccountFailedToInitialize(bytes data);

    /// @notice thrown when Account creation fails due to no version being set
    /// @param data: data returned from failed low-level call
    error AccountFailedToFetchVersion(bytes data);

    /// @notice thrown when factory is not upgradable
    error CannotUpgrade();

    /// @notice thrown account owner is unrecognized via ownerToAccount mapping
    error AccountDoesNotExist();

    /// @notice thrown when caller is not an account
    error CallerMustBeAccount();

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

    /// @return address of account owned by _owner
    /// @param _owner: owner of account
    function ownerToAccount(address _owner) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice create unique account proxy for function caller
    /// @return accountAddress address of account created
    function newAccount() external returns (address payable accountAddress);

    /// @notice update account owner
    /// @param _oldOwner: old owner of account
    /// @param _newOwner: new owner of account
    function updateAccountOwner(address _oldOwner, address _newOwner) external;

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

    /// @notice remove upgradability from factory
    /// @dev cannot be undone
    function removeUpgradability() external;
}
