// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {UpgradedAuth} from "test/utils/UpgradedAuth.sol";

contract UpgradedAccount is UpgradedAuth {
    bytes32 public constant VERSION = "6.9.0";

    constructor() UpgradedAuth(address(0)) {}

    function setInitialOwnership(address _owner) external {
        owner = _owner;
    }
}
