// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

contract UpgradedAccount {
    bytes32 public constant VERSION = "6.9.0";
    address public owner = address(0);
    address public factory = address(0);

    function initialize(address _owner, address _factory) external {
        owner = _owner;
        factory = _factory;
    }
}
