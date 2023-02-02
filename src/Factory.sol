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

    /// @notice bool to determine if factory can be upgraded
    bool public canUpgrade = true;

    /// @notice account implementation
    address public implementation;

    /// @notice settings for accounts
    address public settings;

    /// @notice ERC20 token used to interact with markets
    address public marginAsset;

    /// @notice synthetix address resolver
    address public addressResolver;

    /// @notice gelato ops
    address payable public ops;

    /// @notice mapping of account owner to account created
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
    function upgradeSystem(
        address payable _implementation,
        address _settings,
        address _marginAsset,
        address _addressResolver,
        address payable _ops
    ) external override onlyOwner {
        if (!canUpgrade) revert CannotUpgrade();

        implementation = _implementation;
        settings = _settings;
        marginAsset = _marginAsset;
        addressResolver = _addressResolver;
        ops = _ops;

        emit SystemUpgraded({
            implementation: _implementation,
            settings: _settings,
            marginAsset: _marginAsset,
            addressResolver: _addressResolver,
            ops: _ops
        });
    }

    /// @inheritdoc IFactory
    function removeUpgradability() external override onlyOwner {
        canUpgrade = false;
    }
}
