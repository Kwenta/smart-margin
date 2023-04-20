// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {ISettings} from "./interfaces/ISettings.sol";
import {Owned} from "@solmate/auth/Owned.sol";

contract Settings is ISettings, Owned {
    bool public accountExecutionEnabled = true;

    constructor(address _owner) Owned(_owner) {}

    function setAccountExecutionEnabled(bool _enabled) external onlyOwner {
        accountExecutionEnabled = _enabled;
        emit AccountExecutionEnabledSet(_enabled);
    }
}
