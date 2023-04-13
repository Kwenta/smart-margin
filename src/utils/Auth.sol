// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @notice Authorization mixin for Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
/// @dev This contract is intended to be inherited by the Account contract
abstract contract Auth {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice owner of the account
    address public owner;

    /// @notice mapping of delegate address
    mapping(address delegate => bool) public delegates;

    /// @dev reserved storage space for future contract upgrades
    uint256[20] private __gap;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when an unauthorized caller attempts
    /// to access a caller restricted function
    error Unauthorized();

    /// @notice thrown when the delegate address is invalid
    /// @param delegateAddress: address of the delegate attempting to be added
    error InvalidDelegateAddress(address delegateAddress);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after ownership transfer
    /// @param caller: previous owner
    /// @param newOwner: new owner
    event OwnershipTransferred(
        address indexed caller, address indexed newOwner
    );

    /// @notice emitted after a delegate is added
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being added
    event DelegatedAccountAdded(
        address indexed caller, address indexed delegate
    );

    /// @notice emitted after a delegate is removed
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being removed
    event DelegatedAccountRemoved(
        address indexed caller, address indexed delegate
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @dev sets owner to _owner and not msg.sender
    /// @param _owner The address of the owner
    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @return true if the caller is the owner
    function isOwner() public view virtual returns (bool) {
        return (msg.sender == owner);
    }

    /// @return true if the caller is the owner or a delegate
    function isAuth() public view virtual returns (bool) {
        return (msg.sender == owner || delegates[msg.sender]);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer ownership of the account
    /// @dev only owner can transfer ownership (not delegates)
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) public virtual {
        if (!isOwner()) revert Unauthorized();

        owner = _newOwner;

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    /// @notice Add a delegate to the account
    /// @dev only owner can add a delegate (not delegates)
    /// @param _delegate The address of the delegate
    function addDelegate(address _delegate) public virtual {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        delegates[_delegate] = true;

        emit DelegatedAccountAdded({caller: msg.sender, delegate: _delegate});
    }

    /// @notice Remove a delegate from the account
    /// @dev only owner can remove a delegate (not delegates)
    /// @param _delegate The address of the delegate
    function removeDelegate(address _delegate) public virtual {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || !delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        delete delegates[_delegate];

        emit DelegatedAccountRemoved({caller: msg.sender, delegate: _delegate});
    }
}
