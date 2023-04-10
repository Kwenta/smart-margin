// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {AccountProxy} from "./AccountProxy.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/// @title Kwenta Account Factory
/// @author JaredBorders (jaredborders@pm.me)
/// @notice factory for creating smart margin accounts
/// @dev the factory acts as a beacon for the proxy {AccountProxy.sol} contract(s)
contract Factory is IFactory, Owned {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    bool public canUpgrade = true;

    /// @inheritdoc IFactory
    address public implementation;

    /// @inheritdoc IFactory
    mapping(address accounts => bool exist) public accounts;

    /// @notice mapping of owner to accounts owned by owner
    mapping(address owner => address[] accounts) internal ownerAccounts;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for factory that sets owner
    /// @param _owner: owner of factory
    constructor(address _owner) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function getAccountOwner(address _account)
        public
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

    /// @inheritdoc IFactory
    function getAccountsOwnedBy(address _owner)
        external
        view
        override
        returns (address[] memory)
    {
        return ownerAccounts[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                               OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function updateAccountOwnership(
        address _account,
        address _newOwner,
        address _oldOwner
    ) external override {
        // ensure account is registered by factory
        if (!accounts[_account]) revert AccountDoesNotExist();

        // ensure function caller is the account
        if (msg.sender != _account) revert OnlyAccount();

        uint256 length = ownerAccounts[_oldOwner].length;
        for (uint256 i = 0; i < length;) {
            if (ownerAccounts[_oldOwner][i] == _account) {
                // remove account from ownerAccounts mapping for old owner
                _shiftArrayLeftFrom({
                    _index: i,
                    _array: ownerAccounts[_oldOwner]
                });

                // add account to ownerAccounts mapping for new owner
                ownerAccounts[_newOwner].push(_account);

                return;
            }

            unchecked {
                i++;
            }
        }
    }

    /// @notice shifts every element in the array left from the specified index
    /// @dev index will *NEVER* be out of bounds
    /// @param _index: index to start shifting from
    /// @param _array: array to shift
    /// @custom:example _shiftArrayLeftFrom(1, [1, 2, 3, 4, 5]) => [1, 3, 4, 5]
    function _shiftArrayLeftFrom(uint256 _index, address[] storage _array)
        internal
    {
        uint256 length = _array.length;

        for (uint256 i = _index; i < length - 1;) {
            _array[i] = _array[i + 1];

            unchecked {
                i++;
            }
        }

        _array.pop();
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

        // add account to ownerAccounts mapping
        ownerAccounts[msg.sender].push(accountAddress);

        // set owner of account to caller
        (bool success, bytes memory data) = accountAddress.call(
            abi.encodeWithSignature("setInitialOwnership(address)", msg.sender)
        );
        if (!success) revert FailedToSetAcountOwner(data);

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
    function removeUpgradability() external override onlyOwner {
        canUpgrade = false;
    }
}
