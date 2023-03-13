// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @title Auth Interface
/// @author JaredBorders (jaredborders@pm.me)
interface IAuth {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after ownership transfer
    /// @param user: previous owner
    /// @param newOwner: new owner
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    /// @notice emitted after a delegate is added
    /// @param user: owner of the account
    /// @param delegate: address of the delegate being added
    event DelegatedAccountAdded(address indexed user, address indexed delegate);

    /// @notice emitted after a delegate is removed
    /// @param user: owner of the account
    /// @param delegate: address of the delegate being removed
    event DelegatedAccountRemoved(
        address indexed user, address indexed delegate
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when an unauthorized caller attempts 
    /// to access a caller restricted function
    error Unauthorized();

    /// @notice thrown when the delegate address is invalid
    error InvalidDelegate();

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @return owner of the account
    function owner() external view returns (address);

    /// @notice mapping of delegates who can execute trades
    /// but cannot transfer ownership, add/remove delegates,
    /// nor withdraw/deposit funds from an account
    /// @param _delegate The address of the delegate
    /// @return true if the address is authorized
    function delegates(address _delegate) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @return true if the caller is the owner
    function isOwner() external view returns (bool);

    /// @return true if the caller is the owner or a delegate
    function isAuth() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer ownership of the account
    /// @dev only owner can transfer ownership (not delegates)
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) external;

    /// @notice Add a delegate to the account
    /// @dev only owner can add a delegate (not delegates)
    /// @param _delegate The address of the delegate
    function addDelegate(address _delegate) external;

    /// @notice Remove a delegate from the account
    /// @dev only owner can remove a delegate (not delegates)
    /// @param _delegate The address of the delegate
    function removeDelegate(address _delegate) external;
}
