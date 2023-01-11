// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMarginAccountFactory.sol";
import "./IMarginAccountFactoryStorage.sol";
import "../MarginBase.sol";

/// @title Kwenta MarginAccountFactory Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginAccountFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when new account is created
    /// @param owner: account creator
    /// @param account: address of account that was created
    event NewAccount(address indexed owner, address indexed account);

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

    /// @return version of factory/account
    function VERSION() external view returns (string memory);

    /// @return logic address MarginBase contract acting as user's account
    function implementation() external view returns (MarginBase);

    /// @return address of ERC20 token used to interact with markets
    function marginAsset() external view returns (IERC20);

    /// @return address of persistent storage for all accounts/factories v2.0.0 and later
    function store() external view returns (IMarginAccountFactoryStorage);

    /// @return address of synthetix address resolver
    function addressResolver() external view returns (address);

    /// @return address of settings for accounts
    function marginBaseSettings() external view returns (address);

    /// @return address of gelato ops
    function ops() external view returns (address payable);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice clone MarginBase (i.e. create new account for user)
    /// @dev this contract is the initial owner of cloned MarginBase,
    /// but ownership is transferred after successful initialization
    function newAccount() external returns (address payable accountAddress);
}
