// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOps} from "../interfaces/IOps.sol";

/// @dev Inherit this contract to allow your smart
/// contract to make synchronous fee payments and have
/// call restrictions for functions to be automated.
abstract contract OpsReady {
    error OnlyOps();

    /// @notice address of Gelato Network contract
    address public immutable GELATO;

    /// @notice address of Gelato `Automate` contract
    address public immutable OPS;

    /// @notice internal address representation of ETH (used by Gelato)
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice modifier to restrict access to the `Automate` contract
    modifier onlyOps() {
        if (msg.sender != OPS) revert OnlyOps();
        _;
    }

    constructor(address _gelato, address _ops) {
        GELATO = _gelato;
        OPS = _ops;
    }

    /// @notice transfers fee to gelato for synchronous fee payments
    /// @param _amount: amount of asset to transfer
    /// @param _paymentToken: address of the token to transfer
    function _transfer(uint256 _amount, address _paymentToken) internal {
        if (_paymentToken == ETH) {
            (bool success,) = GELATO.call{value: _amount}("");
            require(success, "OpsReady: ETH transfer failed");
        } else {
            SafeERC20.safeTransfer(IERC20(_paymentToken), GELATO, _amount);
        }
    }

    /// @notice get fee details from `Automate` contract
    /// @return fee amount
    /// @return feeToken address of fee token (or ETH)
    function _getFeeDetails()
        internal
        view
        returns (uint256 fee, address feeToken)
    {
        (fee, feeToken) = IOps(OPS).getFeeDetails();
    }
}
