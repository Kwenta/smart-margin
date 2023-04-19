// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

// https://docs.synthetix.io/contracts/source/interfaces/isystemstatus
interface ISystemStatus {
    function suspendFuturesMarket(bytes32 marketKey, uint256 reason) external;

    function updateAccessControl(
        bytes32 section,
        address account,
        bool canSuspend,
        bool canResume
    ) external;
}
