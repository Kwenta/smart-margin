// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

abstract contract UpgradedAuth {
    address public owner;
    mapping(address delegate => bool) public delegates;

    /// @dev new storage slot to test for storage collisions
    address public storageSlotTest;

    // reduce storage size by 1 slot (19 -> 18)
    uint256[18] private __gap;

    error Unauthorized();
    error InvalidDelegateAddress(address delegateAddress);

    event OwnershipTransferred(
        address indexed caller, address indexed newOwner
    );

    event DelegatedAccountAdded(
        address indexed caller, address indexed delegate
    );

    event DelegatedAccountRemoved(
        address indexed caller, address indexed delegate
    );

    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function isOwner() public view virtual returns (bool) {
        return (msg.sender == owner);
    }

    function isAuth() public view virtual returns (bool) {
        return (msg.sender == owner || delegates[msg.sender]);
    }

    function transferOwnership(address _newOwner) public virtual {
        if (!isOwner()) revert Unauthorized();

        owner = _newOwner;

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    function addDelegate(address _delegate) public virtual {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        delegates[_delegate] = true;

        emit DelegatedAccountAdded({caller: msg.sender, delegate: _delegate});
    }

    function removeDelegate(address _delegate) public virtual {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || !delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        delete delegates[_delegate];

        emit DelegatedAccountRemoved({caller: msg.sender, delegate: _delegate});
    }
}
