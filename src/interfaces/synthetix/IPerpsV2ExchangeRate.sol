// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// Used to fetch a price with a degree of uncertainty, represented as a price +- a confidence interval.
///
/// The confidence interval roughly corresponds to the standard error of a normal distribution.
/// Both the price and confidence are stored in a fixed-point numeric representation,
/// `x * (10^expo)`, where `expo` is the exponent.
///
/// Please refer to the documentation at https://docs.pyth.network/consumers/best-practices for how
/// to how this price safely.
interface IPerpsV2ExchangeRate {
    /// @notice Returns the price of a price feed without any sanity checks.
    /// @dev This function returns the most recent price update in this contract without any recency checks.
    /// This function is unsafe as the returned price update may be arbitrarily far in the past.
    ///
    /// Users of this function should check the `publishTime` in the price to ensure that the returned price is
    /// sufficiently recent for their application. If you are considering using this function, it may be
    /// safer / easier to use either `getPrice` or `getPriceNoOlderThan`.
    /// @return price - please read the documentation of PythStructs.Price to understand how to use this safely.
    /// @return publishTime - unix timestamp describing when the price was published.
    function resolveAndGetLatestPrice(bytes32 assetId)
        external
        view
        returns (uint256 price, uint256 publishTime);
}
