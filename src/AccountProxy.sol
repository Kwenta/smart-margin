// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {IAccountProxy} from "./interfaces/IAccountProxy.sol";

/// @title Kwenta Account Proxy
/// @author OpenZeppelin, JaredBorders (jaredborders@pm.me)
/// @dev This contract implements a proxy that gets the
/// implementation address for each call from the {Beacon}
/// (which in this system is the contract: {Factory.sol}).
/// The beacon address is stored in the storage slot
/// `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
/// conflict with the storage layout of the implementation behind this proxy.
contract AccountProxy is IAccountProxy {
    /*//////////////////////////////////////////////////////////////
                           STORAGE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant _BEACON_STORAGE_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);

    /// @dev struct to store beacon address
    struct AddressSlot {
        address value;
    }

    /// @dev returns the storage slot where the beacon address is stored
    function _getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r.slot := slot
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor for proxy
    /// @param _beaconAddress: address of beacon (i.e. factory address)
    /// @dev {Factory.sol} will store the implementation address,
    /// thus acting as the beacon
    constructor(address _beaconAddress) {
        _getAddressSlot(_BEACON_STORAGE_SLOT).value = _beaconAddress;
    }

    /*//////////////////////////////////////////////////////////////
                              BEACON LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return beacon address (i.e. the factory address)
    function _beacon() internal view returns (address beacon) {
        beacon = _getAddressSlot(_BEACON_STORAGE_SLOT).value;
        if (beacon == address(0)) revert BeaconNotSet();
    }

    /*//////////////////////////////////////////////////////////////
                          IMPLEMENTATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return implementation address (i.e. the account logic address)
    function _implementation() internal returns (address implementation) {
        (bool success, bytes memory data) =
            _beacon().call(abi.encodeWithSignature("implementation()"));
        if (!success) revert BeaconCallFailed();
        implementation = abi.decode(data, (address));
        if (implementation == address(0)) revert ImplementationNotSet();
    }

    /*//////////////////////////////////////////////////////////////
                            FORWARDING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`.
    /// Will run if no other function in the contract matches the call data.
    fallback() external payable {
        _fallback();
    }

    /// @dev Fallback function that delegates calls to the address returned by `_implementation()`.
    /// Will run if call data is empty.
    receive() external payable {
        _fallback();
    }

    /// @notice Delegates the current call to the address returned by `_implementation()`.
    /// @dev This function does not return to its internal call site,
    /// it will return directly to the external caller.
    function _fallback() internal {
        _delegate(_implementation());
    }

    /// @notice delegates the current call to `implementation`.
    /// @dev This function does not return to its internal call site,
    /// it will return directly to the external caller.
    function _delegate(address implementation) internal virtual {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())
            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
