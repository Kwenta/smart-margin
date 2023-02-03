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

    /// @notice emitted when implementation is upgraded
    /// @param implementation: address of new implementation
    event AccountImplementationUpgraded(address implementation);

    /// @notice emitted when settings is upgraded
    /// @param settings: address of new settings
    event SettingsUpgraded(address settings);

    /// @notice emitted when marginAsset is upgraded
    /// @param marginAsset: address of new margin asset
    event MarginAssetUpgraded(address marginAsset);

    /// @notice emitted when addressResolver is upgraded
    /// @param addressResolver: new synthetix address resolver
    event AddressResolverUpgraded(address addressResolver);

    /// @notice emitted when ops is upgraded
    /// @param ops: new gelato ops -- must be payable
    event OpsUpgraded(address payable ops);

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

    /*//////////////////////////////////////////////////////////////
                             UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice upgrade implementation of account which all account proxies currently point to
    /// @dev this *will* impact all existing accounts
    /// @dev future accounts will also point to this new implementation (until 
    /// upgradeAccountImplementation() is called again with a newer implementation)
    /// @dev *DANGER* this function does not check the new implementation for validity,
    /// thus, a bad upgrade could result in severe consequences.
    /// @param _implementation: address of new implementation
    function upgradeAccountImplementation(address _implementation) external;

    /// @dev upgrade settings for all future accounts; existing accounts will not be affected
    /// and will point to settings address they were initially deployed with
    /// @param _settings: address of new settings
    function upgradeSettings(address _settings) external;

    /// @dev upgrade margin asset for all future accounts; existing accounts will not be affected
    /// and will point to margin asset address they were initially deployed with
    /// @param _marginAsset: address of new margin asset
    function upgradeMarginAsset(address _marginAsset) external;

    /// @dev upgrade address resolver for all future accounts; existing accounts will not be affected
    /// and will point to address resolver address they were initially deployed with
    /// @param _addressResolver: new synthetix address resolver
    function upgradeAddressResolver(address _addressResolver) external;

    /// @dev upgrade ops for all future accounts; existing accounts will not be affected
    /// and will point to ops address they were initially deployed with
    /// @param _ops: new gelato ops
    function upgradeOps(address payable _ops) external;

    /// @notice remove upgradability from factory
    /// @dev cannot be undone
    function removeUpgradability() external;
}
