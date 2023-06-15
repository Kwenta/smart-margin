// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {ISettings} from "./interfaces/ISettings.sol";
import {Owned} from "./utils/Owned.sol";

/// @title Kwenta Smart Margin Account Settings
/// @author JaredBorders (jaredborders@pm.me)
contract Settings is ISettings, Owned {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    bool public accountExecutionEnabled = true;

    /// @notice mapping of whitelisted tokens available for swapping via uniswap commands
    mapping(address => bool) internal _whitelistedTokens;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructs the Settings contract
    /// @param _owner: address of the owner of the contract
    constructor(address _owner) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    function whitelistedTokens(address _token)
        external
        view
        override
        returns (bool)
    {
        return _whitelistedTokens[_token];
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    function setAccountExecutionEnabled(bool _enabled)
        external
        override
        onlyOwner
    {
        accountExecutionEnabled = _enabled;

        emit AccountExecutionEnabledSet(_enabled);
    }

    /// @inheritdoc ISettings
    function setTokenWhitelistStatus(address _token, bool _isWhitelisted)
        external
        override
        onlyOwner
    {
        _whitelistedTokens[_token] = _isWhitelisted;

        emit TokenWhitelistStatusUpdated(_token);
    }
}
