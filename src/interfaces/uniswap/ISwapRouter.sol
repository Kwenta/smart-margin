// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "./IUniswapV3SwapCallback.sol";

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Uniswap V3
interface ISwapRouter is IUniswapV3SwapCallback {
    /// tokenIn: The contract address of the inbound token
    /// tokenOut: The contract address of the outbound token
    /// fee: The fee tier of the pool, used to determine the correct pool contract in which to execute the swap
    /// recipient: the destination address of the outbound token
    /// deadline: the unix time after which a swap will fail, to protect against long-pending transactions and wild swings in prices
    /// amountOutMinimum: value should be calculated using our SDK or an onchain price oracle
    ///     this helps protect against getting an unusually bad price for a trade due
    ///     to a front running sandwich or another type of price manipulation
    /// sqrtPriceLimitX96: value can be used to set the limit for the price the swap will push
    ///     the pool to, which can help protect against price impact or for
    ///     setting up logic in a variety of price-relevant mechanisms.
    ///     setting to zero results in this parameter being inactive and
    ///     ensures a swap with the exact input amount
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
