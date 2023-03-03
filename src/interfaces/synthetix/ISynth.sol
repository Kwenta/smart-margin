// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

// https://docs.synthetix.io/contracts/source/interfaces/isynth
interface ISynth {
    // Views
    function currencyKey() external view returns (bytes32);

    function transferableSynths(address account) external view returns (uint256);

    // Mutative functions
    function transferAndSettle(address to, uint256 value) external returns (bool);

    function transferFromAndSettle(address from, address to, uint256 value)
        external
        returns (bool);

    // Restricted: used internally to Synthetix
    function burn(address account, uint256 amount) external;

    function issue(address account, uint256 amount) external;
}
