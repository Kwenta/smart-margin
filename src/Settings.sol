// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {ISettings} from "./interfaces/ISettings.sol";
import {Owned} from "@solmate/auth/Owned.sol";

contract Settings is ISettings, Owned {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/
    
    /// @inheritdoc ISettings
    bool public accountExecutionEnabled = true;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructs the Settings contract
    /// @param _owner: address of the owner of the contract
    constructor(address _owner) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    function setAccountExecutionEnabled(bool _enabled) external onlyOwner {
        accountExecutionEnabled = _enabled;
        emit AccountExecutionEnabledSet(_enabled);
    }
}
