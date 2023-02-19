// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "./IPerpsV2MarketBaseTypes.sol";

interface IPerpsV2Market {
    /* ========== FUNCTION INTERFACE ========== */

    /* ---------- Market Operations ---------- */

    function recomputeFunding() external returns (uint256 lastIndex);

    function transferMargin(int256 marginDelta) external;

    function withdrawAllMargin() external;

    function modifyPosition(int256 sizeDelta, uint256 priceImpactDelta) external;

    function modifyPositionWithTracking(
        int256 sizeDelta,
        uint256 priceImpactDelta,
        bytes32 trackingCode
    ) external;

    function closePosition(uint256 priceImpactDelta) external;

    function closePositionWithTracking(uint256 priceImpactDelta, bytes32 trackingCode) external;

    function liquidatePosition(address account) external;
}
