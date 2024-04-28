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

    /// @notice emitted when the executor fee is updated
    /// @param executorFee: the executor fee
    event ExecutorFeeSet(uint256 executorFee);

    /// @notice emitted when a token is added to or removed from the whitelist
    /// @param token: address of the token
    /// @param isWhitelisted: true if token is whitelisted, false if not
    event TokenWhitelistStatusUpdated(address token, bool isWhitelisted);

    /// @notice emitted when the order flow fee is updated
    /// @param orderFlowFee: the order flow fee
    event OrderFlowFeeSet(uint256 orderFlowFee);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when the executor fee is invalid (e.g. exceeds 100%)
    /// @dev 100% is represented as 100_000
    error InvalidOrderFlowFee();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice gets the maximum order flow fee
    /// @dev 100% is represented as 100_000
    /// @return MAX_ORDER_FLOW_FEE: the maximum order flow fee
    function MAX_ORDER_FLOW_FEE() external view returns (uint256);

    /// @notice gets the Kwenta treasury address
    /// @return TREASURY: the treasury address
    function TREASURY() external view returns (address);

    /// @notice checks if account execution is enabled or disabled
    /// @return enabled: true if account execution is enabled, false if disabled
    function accountExecutionEnabled() external view returns (bool);

    /// @notice gets the conditional order executor fee
    /// @return executorFee: the executor fee
    function executorFee() external view returns (uint256);

    /// @notice gets the order flow fee
    /// @dev three decimal places, e.g. 1 == 0.001%
    /// @custom:example 10 == 0.01% && 100 == 0.1% && 1_000 == 1% && 10_000 == 10%
    /// @dev cannot exceed 100_000 (100%)
    /// @return orderFlowFee: the order flow fee
    function orderFlowFee() external view returns (uint256);

    /// @notice checks if token is whitelisted
    /// @param _token: address of the token to check
    /// @return true if token is whitelisted, false if not
    function isTokenWhitelisted(address _token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice enables or disables account execution
    /// @param _enabled: true if account execution is enabled, false if disabled
    function setAccountExecutionEnabled(bool _enabled) external;

    /// @notice sets the conditional order executor fee
    /// @param _executorFee: the executor fee
    function setExecutorFee(uint256 _executorFee) external;

    /// @notice adds/removes token to/from whitelist
    /// @dev does not check if token was previously whitelisted
    /// @param _token: address of the token to add
    /// @param _isWhitelisted: true if token is to be whitelisted, false if not
    function setTokenWhitelistStatus(address _token, bool _isWhitelisted)
        external;

    /// @notice sets the order flow fee
    /// @dev three decimal places, e.g. 1 == 0.001%
    /// @custom:example 10 == 0.01% && 100 == 0.1% && 1_000 == 1% && 10_000 == 10%
    /// @dev cannot exceed 100_000 (100%)
    /// @param _orderFlowFee: the order flow fee
    function setOrderFlowFee(uint256 _orderFlowFee) external;
}
