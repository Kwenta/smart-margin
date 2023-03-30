// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "./IPerpsV2MarketBaseTypes.sol";

// Helper Interface - used in tests and to provide a consolidated PerpsV2 interface for users/integrators.

interface IPerpsV2MarketConsolidated {
    /* ========== TYPES ========== */

    enum OrderType {
        Atomic,
        Delayed,
        Offchain
    }

    enum Status {
        Ok,
        InvalidPrice,
        InvalidOrderType,
        PriceOutOfBounds,
        CanLiquidate,
        CannotLiquidate,
        MaxMarketSizeExceeded,
        MaxLeverageExceeded,
        InsufficientMargin,
        NotPermitted,
        NilOrder,
        NoPositionOpen,
        PriceTooVolatile,
        PriceImpactToleranceExceeded,
        PositionFlagged,
        PositionNotFlagged
    }

    /* @dev: See IPerpsV2MarketBaseTypes */
    struct Position {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    /* @dev: See IPerpsV2MarketBaseTypes */
    struct DelayedOrder {
        bool isOffchain;
        int128 sizeDelta;
        uint128 desiredFillPrice;
        uint128 targetRoundId;
        uint128 commitDeposit;
        uint128 keeperDeposit;
        uint256 executableAtTime;
        uint256 intentionTime;
        bytes32 trackingCode;
    }

    /* ========== Views ========== */

    /* ---------- Market Details ---------- */

    function marketKey() external view returns (bytes32 key);

    function baseAsset() external view returns (bytes32 key);

    function marketSize() external view returns (uint128 size);

    function marketSkew() external view returns (int128 skew);

    function fundingLastRecomputed() external view returns (uint32 timestamp);

    function fundingRateLastRecomputed()
        external
        view
        returns (int128 fundingRate);

    function fundingSequence(uint256 index)
        external
        view
        returns (int128 netFunding);

    function positions(address account)
        external
        view
        returns (Position memory);

    function delayedOrders(address account)
        external
        view
        returns (DelayedOrder memory);

    function assetPrice() external view returns (uint256 price, bool invalid);

    function fillPrice(int256 sizeDelta)
        external
        view
        returns (uint256 price, bool invalid);

    function marketSizes()
        external
        view
        returns (uint256 long, uint256 short);

    function marketDebt()
        external
        view
        returns (uint256 debt, bool isInvalid);

    function currentFundingRate() external view returns (int256 fundingRate);

    function currentFundingVelocity()
        external
        view
        returns (int256 fundingVelocity);

    function unrecordedFunding()
        external
        view
        returns (int256 funding, bool invalid);

    function fundingSequenceLength() external view returns (uint256 length);

    /* ---------- Position Details ---------- */

    function notionalValue(address account)
        external
        view
        returns (int256 value, bool invalid);

    function profitLoss(address account)
        external
        view
        returns (int256 pnl, bool invalid);

    function accruedFunding(address account)
        external
        view
        returns (int256 funding, bool invalid);

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

    function isFlagged(address account) external view returns (bool);

    function canLiquidate(address account) external view returns (bool);

    function orderFee(
        int256 sizeDelta,
        IPerpsV2MarketBaseTypes.OrderType orderType
    ) external view returns (uint256 fee, bool invalid);

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
            Status status
        );

    /* ========== Market ========== */
    function recomputeFunding() external returns (uint256 lastIndex);

    function transferMargin(int256 marginDelta) external;

    function withdrawAllMargin() external;

    function modifyPosition(int256 sizeDelta, uint256 desiredFillPrice)
        external;

    function modifyPositionWithTracking(
        int256 sizeDelta,
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    function closePosition(uint256 desiredFillPrice) external;

    function closePositionWithTracking(
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    /* ========== Liquidate    ========== */

    function flagPosition(address account) external;

    function liquidatePosition(address account) external;

    function forceLiquidatePosition(address account) external;

    /* ========== Delayed Intent ========== */
    function submitCloseOffchainDelayedOrderWithTracking(
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    function submitCloseDelayedOrderWithTracking(
        uint256 desiredTimeDelta,
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    function submitDelayedOrder(
        int256 sizeDelta,
        uint256 desiredTimeDelta,
        uint256 desiredFillPrice
    ) external;

    function submitDelayedOrderWithTracking(
        int256 sizeDelta,
        uint256 desiredTimeDelta,
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    function submitOffchainDelayedOrder(
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) external;

    function submitOffchainDelayedOrderWithTracking(
        int256 sizeDelta,
        uint256 desiredFillPrice,
        bytes32 trackingCode
    ) external;

    /* ========== Delayed Execution ========== */

    function executeDelayedOrder(address account) external;

    function executeOffchainDelayedOrder(
        address account,
        bytes[] calldata priceUpdateData
    ) external payable;

    function cancelDelayedOrder(address account) external;

    function cancelOffchainDelayedOrder(address account) external;

    /* ========== Events ========== */

    event PositionModified(
        uint256 indexed id,
        address indexed account,
        uint256 margin,
        int256 size,
        int256 tradeSize,
        uint256 lastPrice,
        uint256 fundingIndex,
        uint256 fee,
        int256 skew
    );

    event MarginTransferred(address indexed account, int256 marginDelta);

    event PositionFlagged(
        uint256 id, address account, address flagger, uint256 timestamp
    );

    event PositionLiquidated(
        uint256 id,
        address account,
        address liquidator,
        int256 size,
        uint256 price,
        uint256 fee
    );

    event FundingRecomputed(
        int256 funding, int256 fundingRate, uint256 index, uint256 timestamp
    );

    event PerpsTracking(
        bytes32 indexed trackingCode,
        bytes32 baseAsset,
        bytes32 marketKey,
        int256 sizeDelta,
        uint256 fee
    );

    event DelayedOrderRemoved(
        address indexed account,
        bool isOffchain,
        uint256 currentRoundId,
        int256 sizeDelta,
        uint256 targetRoundId,
        uint256 commitDeposit,
        uint256 keeperDeposit,
        bytes32 trackingCode
    );

    event DelayedOrderSubmitted(
        address indexed account,
        bool isOffchain,
        int256 sizeDelta,
        uint256 targetRoundId,
        uint256 intentionTime,
        uint256 executableAtTime,
        uint256 commitDeposit,
        uint256 keeperDeposit,
        bytes32 trackingCode
    );
}
