// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IFactory, Account} from "./interfaces/IFactory.sol";
import {MinimalProxyFactory} from "./utils/MinimalProxyFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title Kwenta Account Factory
/// @author JaredBorders (jaredborders@pm.me)
/// @notice Mutable factory for creating new accounts
contract Factory is IFactory, Initializable, UUPSUpgradeable, MinimalProxyFactory, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice current version of factory/account
    bytes32 public version;

    /// @notice account logic
    Account public logic;

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
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for factory
    /// @param _owner: owner of factory
    /// @param _version: version of factory/account
    /// @param _marginAsset: address of ERC20 token used to interact with markets
    /// @param _addressResolver: address of synthetix address resolver
    /// @param _settings: address of settings for accounts
    /// @param _ops: contract address for gelato ops -- must be payable
    function initialize(
        address _owner,
        bytes32 _version,
        address _marginAsset,
        address _addressResolver,
        address _settings,
        address payable _ops
    ) public initializer {
        /// @dev transfer ownership to owner
        transferOwnership(_owner);

        version = _version;
        marginAsset = _marginAsset;
        addressResolver = _addressResolver;
        settings = _settings;
        ops = _ops;

        /// @dev deploy logic for proxy
        logic = new Account();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

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

        // create account
        accountAddress = payable(
            _cloneAsMinimalProxy(address(logic), "Creation failure")
        );

        // update creator to account mapping
        creatorToAccount[msg.sender] = accountAddress;

        // initialize new account
        Account account = Account(accountAddress);
        account.initialize(
            address(marginAsset),
            addressResolver,
            settings,
            ops
        );

        // transfer ownership of account to caller
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, accountAddress, version);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice
    /// Factory state is mutable to allow for upgrades. The following setters
    /// will *NOT* impact existing accounts. Only *NEW* accounts will be affected.
    /// The setters are only callable by the owner of the factory.

    /// @inheritdoc IFactory
    function setVersion(bytes32 _version) external override onlyOwner {
        version = _version;
    }

    /// @inheritdoc IFactory
    function setLogic(address payable _logic) external override onlyOwner {
        logic = Account(_logic);
    }

    /// @inheritdoc IFactory
    function setSettings(address _settings) external override onlyOwner {
        settings = _settings;
    }

    /// @inheritdoc IFactory
    function setMarginAsset(address _marginAsset) external override onlyOwner {
        marginAsset = _marginAsset;
    }

    /// @inheritdoc IFactory
    function setAddressResolver(address _addressResolver)
        external
        override
        onlyOwner
    {
        addressResolver = _addressResolver;
    }

    /// @inheritdoc IFactory
    function setOps(address payable _ops) external override onlyOwner {
        ops = _ops;
    }
}
