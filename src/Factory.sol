// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {AccountProxy} from "./AccountProxy.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Owned} from "./utils/Owned.sol";

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

    /// @notice mapping of account creator to account created
    mapping(address => address) public creatorToAccount;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier isUpgradable() {
        if (!canUpgrade) revert CannotUpgrade();

        _;
    }

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
    ) {
        transferOwnership(_owner);
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
        if (creatorToAccount[msg.sender] != address(0)) {
            revert AlreadyCreatedAccount(creatorToAccount[msg.sender]);
        }

        // create account and set beacon to this address (i.e. factory address)
        accountAddress = payable(address(new AccountProxy(address(this))));

        // update creator to account mapping
        creatorToAccount[msg.sender] = accountAddress;

        // initialize new account
        (bool success, bytes memory data) = accountAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                msg.sender,
                marginAsset,
                addressResolver,
                settings,
                ops
            )
        );
        if (!success) revert AccountCreationFailed(data);

        // determine version for the following event
        (success, data) = accountAddress.call(
            abi.encodeWithSignature("VERSION()")
        );
        if (!success) revert AccountCreationFailed(data);

        emit NewAccount({
            creator: msg.sender,
            account: accountAddress,
            version: abi.decode(data, (bytes32))
        });
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function upgradeSystem(
        address payable _implementation,
        address _settings,
        address _marginAsset,
        address _addressResolver,
        address payable _ops
    ) external onlyOwner isUpgradable {
        require(_implementation != address(0), "Invalid implementation");
        require(_settings != address(0), "Invalid settings");
        require(_marginAsset != address(0), "Invalid marginAsset");
        require(_addressResolver != address(0), "Invalid addressResolver");
        require(_ops != address(0), "Invalid ops");

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
}
