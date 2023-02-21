// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOps} from "../interfaces/IOps.sol";

/// @dev Inherit this contract to allow your smart
/// contract to make synchronous fee payments and have
/// call restrictions for functions to be automated.
abstract contract OpsReady {
    error OnlyOps();
    error EthTransferFailed();

    /// @notice address of Gelato Network contract
    address public constant GELATO = 0x01051113D81D7d6DA508462F2ad6d7fD96cF42Ef; // Optimism
    // address public constant GELATO = 0xF82D64357D9120a760e1E4C75f646C0618eFc2F3; // Optimism Goerli

    /// @notice address of Gelato `Automate` contract
    address public constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c; // Optimism
    // address public constant OPS = 0x255F82563b5973264e89526345EcEa766DB3baB2; // Optimism Goerli

    /// @notice address of Gelato `OpsProxyFactory` contract
    address private constant OPS_PROXY_FACTORY = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F; // Optimism
    // address private constant OPS_PROXY_FACTORY = 0x644CB00854EDC55FE8CCC9c1967BABb22F08Ad2f; // Optimism Goerli

    /// @notice internal address representation of ETH (used by Gelato)
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice modifier to restrict access to the `Automate` contract
    modifier onlyOps() {
        if (msg.sender != OPS) revert OnlyOps();
        _;
    }

    /// @notice transfers fee to gelato for synchronous fee payments
    /// @param _amount: amount of asset to transfer
    /// @param _paymentToken: address of the token to transfer
    function _transfer(uint256 _amount, address _paymentToken) internal {
        if (_paymentToken == ETH) {
            (bool success,) = GELATO.call{value: _amount}("");
            if (!success) revert EthTransferFailed();
        } else {
            SafeERC20.safeTransfer(IERC20(_paymentToken), GELATO, _amount);
        }
    }

    /// @notice get fee details from `Automate` contract
    /// @return fee amount
    /// @return feeToken address of fee token (or ETH)
    function _getFeeDetails() internal view returns (uint256 fee, address feeToken) {
        (fee, feeToken) = IOps(OPS).getFeeDetails();
    }
}
