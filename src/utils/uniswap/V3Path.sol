// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {BytesLib} from "src/utils/uniswap/BytesLib.sol";
import {Constants} from "src/utils/uniswap//Constants.sol";

/// @title Functions for manipulating path data for multihop swaps
library V3Path {
    using BytesLib for bytes;

    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes calldata path)
        internal
        pure
        returns (bool)
    {
        return path.length >= Constants.MULTIPLE_V3_POOLS_MIN_LENGTH;
    }

    function decodeFirstToken(bytes calldata path)
        internal
        pure
        returns (address tokenA)
    {
        tokenA = path.toAddress();
    }

    /// @notice Skips a token + fee element
    /// @param path The swap path
    function skipToken(bytes calldata path)
        internal
        pure
        returns (bytes calldata)
    {
        return path[Constants.NEXT_V3_POOL_OFFSET:];
    }
}
