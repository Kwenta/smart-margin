// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @title Kwenta Account Proxy Interface
/// @author JaredBorders (jaredborders@pm.me)
interface IAccountProxy {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev thrown if beacon is not set to a valid address
    error BeaconNotSet();

    /// @dev thrown if implementation is not set to a valid address
    error ImplementationNotSet();

    /// @dev thrown if beacon call fails
    error BeaconCallFailed();
}
