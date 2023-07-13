// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @dev Inherit this contract to allow your smart
/// contract to make synchronous fee payments and have
/// call restrictions for functions to be automated.
abstract contract OpsReady {
    /// @notice address of Gelato Network contract
    address public immutable GELATO;

    /// @notice address of Gelato `Automate` contract
    address public immutable OPS;

    /// @notice internal address representation of ETH (used by Gelato)
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice sets the addresses of the Gelato Network contracts
    /// @param _gelato: address of the Gelato Network contract
    /// @param _ops: address of the Gelato `Automate` contract
    constructor(address _gelato, address _ops) {
        GELATO = _gelato;
        OPS = _ops;
    }

    /// @notice transfers fee (in ETH) to gelato for synchronous fee payments
    /// @dev happens at task execution time
    /// @param _amount: amount of asset to transfer
    function _transfer(uint256 _amount) internal {
        (bool success,) = GELATO.call{value: _amount}("");
        require(success, "OpsReady: ETH transfer failed");
    }
}
