// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface ISynth {
    function issue(address account, uint256 amount) external;
}
