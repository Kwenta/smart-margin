// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IPerpsV2DynamicFeesModule {
    /// @dev Updates the minKeeperFee in PerpsV2MarketSettings
    function setMinKeeperFee() external returns (bool success);

    function getParameters()
        external
        view
        returns (
            uint256 profitMarginUSD,
            uint256 profitMarginPercent,
            uint256 minKeeperFeeUpperBound,
            uint256 minKeeperFeeLowerBound,
            uint256 gasUnitsL1,
            uint256 gasUnitsL2,
            uint256 lastUpdatedAtTime
        );
}
