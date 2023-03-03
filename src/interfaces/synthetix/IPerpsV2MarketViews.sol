// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import "./IPerpsV2MarketBaseTypes.sol";

interface IPerpsV2MarketViews {
    /* ---------- Market Details ---------- */

    function marketKey() external view returns (bytes32 key);

    function baseAsset() external view returns (bytes32 key);

    function marketSize() external view returns (uint128 size);

    function marketSkew() external view returns (int128 skew);

    function fundingLastRecomputed() external view returns (uint32 timestamp);

    function fundingSequence(uint256 index) external view returns (int128 netFunding);

    function positions(address account)
        external
        view
        returns (IPerpsV2MarketBaseTypes.Position memory);

    function assetPrice() external view returns (uint256 price, bool invalid);

    function marketSizes() external view returns (uint256 long, uint256 short);

    function marketDebt() external view returns (uint256 debt, bool isInvalid);

    function currentFundingRate() external view returns (int256 fundingRate);

    function currentFundingVelocity() external view returns (int256 fundingVelocity);

    function unrecordedFunding() external view returns (int256 funding, bool invalid);

    function fundingSequenceLength() external view returns (uint256 length);

    /* ---------- Position Details ---------- */

    function notionalValue(address account) external view returns (int256 value, bool invalid);

    function profitLoss(address account) external view returns (int256 pnl, bool invalid);

    function accruedFunding(address account) external view returns (int256 funding, bool invalid);

    function remainingMargin(address account)
        external
        view
        returns (uint256 marginRemaining, bool invalid);

    function accessibleMargin(address account)
        external
        view
        returns (uint256 marginAccessible, bool invalid);

    function liquidationPrice(address account)
        external
        view
        returns (uint256 price, bool invalid);

    function liquidationFee(address account) external view returns (uint256);

    function canLiquidate(address account) external view returns (bool);

    function orderFee(int256 sizeDelta, IPerpsV2MarketBaseTypes.OrderType orderType)
        external
        view
        returns (uint256 fee, bool invalid);

    function postTradeDetails(
        int256 sizeDelta,
        uint256 tradePrice,
        IPerpsV2MarketBaseTypes.OrderType orderType,
        address sender
    )
        external
        view
        returns (
            uint256 margin,
            int256 size,
            uint256 price,
            uint256 liqPrice,
            uint256 fee,
            IPerpsV2MarketBaseTypes.Status status
        );
}
