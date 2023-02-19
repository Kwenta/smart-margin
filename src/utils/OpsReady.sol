// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOps} from "../interfaces/IOps.sol";

/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
abstract contract OpsReady {
    /// @notice address of Gelato `Automate` contract address on Optimism
    address public constant OPS = 0x340759c8346A1E6Ed92035FB8B6ec57cE1D82c2c;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice modifier to restrict access to the `Automate` contract
    modifier onlyOps() {
        require(msg.sender == OPS, "OpsReady: onlyOps");
        _;
    }

    function gelato() public view returns (address payable) {
        return IOps(OPS).gelato();
    }

    /// @notice helper function to transfer funds to the `Automate` contract
    /// @param _amount: amount of asset to transfer
    /// @param _paymentToken: address of the token to transfer
    function _transfer(uint256 _amount, address _paymentToken) internal {
        if (_paymentToken == ETH) {
            (bool success,) = gelato().call{value: _amount}("");
            require(success, "_transfer: ETH transfer failed");
        } else {
            SafeERC20.safeTransfer(IERC20(_paymentToken), gelato(), _amount);
        }
    }
}
