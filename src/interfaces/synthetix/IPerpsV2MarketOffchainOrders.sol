// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

interface IPerpsV2MarketOffchainOrders {
    function submitOffchainDelayedOrder(
        int256 sizeDelta,
        uint256 priceImpactDelta
    ) external;

    function submitOffchainDelayedOrderWithTracking(
        int256 sizeDelta,
        uint256 priceImpactDelta,
        bytes32 trackingCode
    ) external;

    function cancelOffchainDelayedOrder(address account) external;

    function executeOffchainDelayedOrder(
        address account,
        bytes[] calldata priceUpdateData
    ) external payable;
}
