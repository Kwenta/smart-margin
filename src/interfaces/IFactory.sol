// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {Account} from "../Account.sol";
import {IFactory} from "./IFactory.sol";

/// @title Kwenta Factory Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when new account is created
    /// @param creator: account creator (address that called newAccount())
    /// @param account: address of account that was created
    event NewAccount(
        address indexed creator,
        address indexed account,
        bytes32 version
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when newAccount() is called
    /// by an address which has already made an account
    /// @param account: address of account previously created
    error AlreadyCreatedAccount(address account);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @return version: version of factory/account
    function version() external view returns (bytes32);

    /// @return logic: account logic address
    function logic() external view returns (Account);

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

    /// @notice clone Account (i.e. create new account for user)
    /// @dev this contract is the initial owner of cloned Account,
    /// but ownership is transferred after successful initialization
    /// @return accountAddress address of account created
    function newAccount() external returns (address payable accountAddress);

    /// @notice set new version of factory/account
    /// @param _version: new version of factory/account
    function setVersion(bytes32 _version) external;

    /// @notice set new account logic
    /// @param _logic: new account logic address
    function setLogic(address payable _logic) external;

    /// @notice set new settings for accounts
    /// @param _settings: new settings for accounts
    function setSettings(address _settings) external;

    /// @notice set new ERC20 token used to interact with markets
    /// @param _marginAsset: new ERC20 token used to interact with markets
    function setMarginAsset(address _marginAsset) external;

    /// @notice set new synthetix address resolver
    /// @param _addressResolver: new synthetix address resolver
    function setAddressResolver(address _addressResolver) external;

    /// @notice set new gelato ops
    /// @param _ops: new gelato ops -- must be payable
    function setOps(address payable _ops) external;
}
