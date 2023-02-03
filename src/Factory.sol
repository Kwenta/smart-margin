// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {AccountProxy} from "./AccountProxy.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/// @title Kwenta Account Factory
/// @author JaredBorders (jaredborders@pm.me)
/// @notice Mutable factory for creating smart margin accounts
/// @dev This contract acts as a Beacon for the {AccountProxy.sol} contract
contract Factory is IFactory, Owned {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    bool public canUpgrade = true;

    /// @inheritdoc IFactory
    address public implementation;

    /// @inheritdoc IFactory
    address public settings;

    /// @inheritdoc IFactory
    address public marginAsset;

    /// @inheritdoc IFactory
    address public addressResolver;

    /// @inheritdoc IFactory
    address payable public ops;

    /// @inheritdoc IFactory
    mapping(address => address) public ownerToAccount;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for factory
    /// @param _owner: owner of factory
    /// @param _marginAsset: address of ERC20 token used to interact with markets
    /// @param _addressResolver: address of synthetix address resolver
    /// @param _settings: address of settings for accounts
    /// @param _ops: contract address for gelato ops -- must be payable
    /// @param _implementation: address of account implementation
    constructor(
        address _owner,
        address _marginAsset,
        address _addressResolver,
        address _settings,
        address payable _ops,
        address _implementation
    ) Owned(_owner) {
        marginAsset = _marginAsset;
        addressResolver = _addressResolver;
        settings = _settings;
        ops = _ops;
        implementation = _implementation;
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function newAccount()
        external
        override
        returns (address payable accountAddress)
    {
        /// @dev ensure one account per address
        if (ownerToAccount[msg.sender] != address(0)) {
            revert OnlyOneAccountPerAddress(ownerToAccount[msg.sender]);
        }

        // create account and set beacon to this address (i.e. factory address)
        accountAddress = payable(address(new AccountProxy(address(this))));

        // update owner to account mapping
        ownerToAccount[msg.sender] = accountAddress;

        // initialize new account
        (bool success, bytes memory data) = accountAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                msg.sender, // caller will be set as owner
                marginAsset,
                addressResolver,
                settings,
                ops,
                address(this)
            )
        );
        if (!success) revert AccountFailedToInitialize(data);

        // determine version for the following event
        (success, data) = accountAddress.call(
            abi.encodeWithSignature("VERSION()")
        );
        if (!success) revert AccountFailedToFetchVersion(data);

        emit NewAccount({
            creator: msg.sender,
            account: accountAddress,
            version: abi.decode(data, (bytes32))
        });
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function updateAccountOwner(address _oldOwner, address _newOwner)
        external
        override
    {
        /// @dev ensure _newOwner does not already have an account
        if (ownerToAccount[_newOwner] != address(0)) {
            revert OnlyOneAccountPerAddress(ownerToAccount[_newOwner]);
        }

        // get account address
        address account = ownerToAccount[_oldOwner];

        // ensure account exists
        if (account == address(0)) revert AccountDoesNotExist();

        // ensure account owned by _oldOwner is the caller
        if (msg.sender != account) revert CallerMustBeAccount();

        delete ownerToAccount[_oldOwner];
        ownerToAccount[_newOwner] = account;
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADABILITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function upgradeAccountImplementation(address _implementation)
        external
        override
        onlyOwner
    {
        if (!canUpgrade) revert CannotUpgrade();
        implementation = _implementation;
        emit AccountImplementationUpgraded({implementation: _implementation});
    }

    /// @inheritdoc IFactory
    function upgradeSettings(address _settings) external override onlyOwner {
        if (!canUpgrade) revert CannotUpgrade();
        settings = _settings;
        emit SettingsUpgraded({settings: _settings});
    }

    /// @inheritdoc IFactory
    function upgradeMarginAsset(address _marginAsset)
        external
        override
        onlyOwner
    {
        if (!canUpgrade) revert CannotUpgrade();
        marginAsset = _marginAsset;
        emit MarginAssetUpgraded({marginAsset: _marginAsset});
    }

    /// @inheritdoc IFactory
    function upgradeAddressResolver(address _addressResolver)
        external
        override
        onlyOwner
    {
        if (!canUpgrade) revert CannotUpgrade();
        addressResolver = _addressResolver;
        emit AddressResolverUpgraded({addressResolver: _addressResolver});
    }

    /// @inheritdoc IFactory
    function upgradeOps(address payable _ops) external override onlyOwner {
        if (!canUpgrade) revert CannotUpgrade();
        ops = _ops;
        emit OpsUpgraded({ops: _ops});
    }

    /// @inheritdoc IFactory
    function removeUpgradability() external override onlyOwner {
        canUpgrade = false;
    }
}
