// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Constants} from "./Constants.sol";

/// @title Library for Bytes Manipulation
library BytesLib {
    error SliceOutOfBounds();

    /// @notice Decode the first and last tokens in `_bytes` as addresses
    /// @dev Number of pools is derived from the length of `_bytes`
    /// @param _bytes The input bytes string to slice
    /// @return tokenIn The first token in of the first given pool
    /// @return tokenOut The last token out of the last given pool
    function toSwap(bytes calldata _bytes)
        internal
        pure
        returns (address tokenIn, address tokenOut)
    {
        uint256 numberOfPools = _bytes.length / Constants.V3_POP_OFFSET;
        assembly {
            tokenIn := shr(96, calldataload(_bytes.offset))
            tokenOut :=
                shr(96, calldataload(add(_bytes.offset, mul(numberOfPools, 23))))
        }
    }

    /// @notice Decode the `_arg`-th element in `_bytes` as a dynamic array
    /// @dev The decoding of `length` and `offset` is universal,
    /// whereas the type declaration of `res` instructs the compiler how to read it.
    /// @param _bytes The input bytes string to slice
    /// @param _arg The index of the argument to extract
    /// @return length Length of the array
    /// @return offset Pointer to the data part of the array
    function toLengthOffset(bytes calldata _bytes, uint256 _arg)
        internal
        pure
        returns (uint256 length, uint256 offset)
    {
        uint256 relativeOffset;
        assembly {
            // The offset of the `_arg`-th element is `32 * arg`, which stores the offset of the length pointer.
            // shl(5, x) is equivalent to mul(32, x)
            let lengthPtr :=
                add(_bytes.offset, calldataload(add(_bytes.offset, shl(5, _arg))))
            length := calldataload(lengthPtr)
            offset := add(lengthPtr, 0x20)
            relativeOffset := sub(offset, _bytes.offset)
        }
        if (_bytes.length < length + relativeOffset) revert SliceOutOfBounds();
    }

    /// @notice Decode the `_arg`-th element in `_bytes` as `bytes`
    /// @param _bytes The input bytes string to extract a bytes string from
    /// @param _arg The index of the argument to extract
    function toBytes(bytes calldata _bytes, uint256 _arg)
        internal
        pure
        returns (bytes calldata res)
    {
        (uint256 length, uint256 offset) = toLengthOffset(_bytes, _arg);
        assembly {
            res.length := length
            res.offset := offset
        }
    }
}
