// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAuth} from "./interfaces/IAuth.sol";

/// @notice Authorization mixin for Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
contract Auth is IAuth {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAuth
    address public owner;

    /// @inheritdoc IAuth
    mapping(address delegate => bool) public delegates;

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

    /// @inheritdoc IAuth
    function isOwner() public view returns (bool) {
        return (msg.sender == owner);
    }

    /// @inheritdoc IAuth
    function isAuth() public view returns (bool) {
        return (msg.sender == owner || delegates[msg.sender]);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAuth
    function transferOwnership(address _newOwner) public {
        if (!isOwner()) revert Unauthorized();

        owner = _newOwner;

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    /// @inheritdoc IAuth
    function addDelegate(address _delegate) public {
        if (!isOwner()) revert Unauthorized();
        if (_delegate == address(0) || delegates[_delegate]) {
            revert InvalidDelegate();
        }

        delegates[_delegate] = true;

        emit DelegatedAccountAdded({user: msg.sender, delegate: _delegate});
    }

    /// @inheritdoc IAuth
    function removeDelegate(address _delegate) public {
        if (!isOwner()) revert Unauthorized();
        if (_delegate == address(0) || !delegates[_delegate]) {
            revert InvalidDelegate();
        }

        delete delegates[_delegate];

        emit DelegatedAccountRemoved({user: msg.sender, delegate: _delegate});
    }
}
