// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface ISettings {
    event AccountExecutionEnabledSet(bool enabled);

    function accountExecutionEnabled() external view returns (bool);
    function setAccountExecutionEnabled(bool _enabled) external;
}
