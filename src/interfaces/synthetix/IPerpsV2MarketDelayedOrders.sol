// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IPerpsV2MarketDelayedOrders {
    function submitDelayedOrder(
        int256 sizeDelta,
        uint256 priceImpactDelta,
        uint256 desiredTimeDelta
    ) external;

    function submitDelayedOrderWithTracking(
        int256 sizeDelta,
        uint256 priceImpactDelta,
        uint256 desiredTimeDelta,
        bytes32 trackingCode
    ) external;

    function cancelDelayedOrder(address account) external;

    function executeDelayedOrder(address account) external;
}
