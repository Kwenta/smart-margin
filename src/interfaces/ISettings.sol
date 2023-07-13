// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @title Kwenta Smart Margin Account Settings Interface
/// @author JaredBorders (jaredborders@pm.me)
interface ISettings {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when account execution is enabled or disabled
    /// @param enabled: true if account execution is enabled, false if disabled
    event AccountExecutionEnabledSet(bool enabled);

    /// @notice emitted when a token is added to or removed from the whitelist
    /// @param token: address of the token
    event TokenWhitelistStatusUpdated(address token);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice checks if account execution is enabled or disabled
    /// @return enabled: true if account execution is enabled, false if disabled
    function accountExecutionEnabled() external view returns (bool);

    /// @notice checks if token is whitelisted
    /// @param _token: address of the token to check
    /// @return true if token is whitelisted, false if not
    function isWhitelistedTokens(address _token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice enables or disables account execution
    /// @param _enabled: true if account execution is enabled, false if disabled
    function setAccountExecutionEnabled(bool _enabled) external;

    /// @notice adds/removes token to/from whitelist
    /// @dev does not check if token was previously whitelisted
    /// @param _token: address of the token to add
    /// @param _isWhitelisted: true if token is to be whitelisted, false if not
    function setTokenWhitelistStatus(address _token, bool _isWhitelisted)
        external;
}
