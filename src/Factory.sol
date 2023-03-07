// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

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
    address public settings;

    /// @inheritdoc IFactory
    address public events;

    /// @inheritdoc IFactory
    address public implementation;

    /// @inheritdoc IFactory
    mapping(address accounts => bool exist) public accounts;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for factory
    /// @param _owner: owner of factory
    /// @param _settings: address of settings contract for accounts
    /// @param _events: address of events contract for accounts
    /// @param _implementation: address of account implementation
    constructor(
        address _owner,
        address _settings,
        address _events,
        address _implementation
    ) Owned(_owner) {
        settings = _settings;
        events = _events;
        implementation = _implementation;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function getAccountOwner(address _account)
        external
        view
        override
        returns (address)
    {
        // ensure account is registered
        if (!accounts[_account]) revert AccountDoesNotExist();

        // fetch owner from account
        (bool success, bytes memory data) =
            _account.staticcall(abi.encodeWithSignature("owner()"));
        assert(success); // should never fail (account is a contract

        return abi.decode(data, (address));
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
        // create account and set beacon to this address (i.e. factory address)
        accountAddress = payable(address(new AccountProxy(address(this))));

        // add account to accounts mapping
        accounts[accountAddress] = true;

        // initialize new account
        (bool success, bytes memory data) = accountAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,address)",
                msg.sender, // caller will be set as owner
                settings,
                events,
                address(this)
            )
        );
        if (!success) revert AccountFailedToInitialize(data);

        // determine version for the following event
        (success, data) =
            accountAddress.call(abi.encodeWithSignature("VERSION()"));
        if (!success) revert AccountFailedToFetchVersion(data);

        emit NewAccount({
            creator: msg.sender,
            account: accountAddress,
            version: abi.decode(data, (bytes32))
        });
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
    function upgradeEvents(address _events) external override onlyOwner {
        if (!canUpgrade) revert CannotUpgrade();
        events = _events;
        emit EventsUpgraded({events: _events});
    }

    /// @inheritdoc IFactory
    function removeUpgradability() external override onlyOwner {
        canUpgrade = false;
    }
}
