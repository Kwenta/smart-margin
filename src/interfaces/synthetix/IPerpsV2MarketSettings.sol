// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

interface IPerpsV2MarketSettings {
    struct Parameters {
        uint256 takerFee;
        uint256 makerFee;
        uint256 overrideCommitFee;
        uint256 takerFeeDelayedOrder;
        uint256 makerFeeDelayedOrder;
        uint256 takerFeeOffchainDelayedOrder;
        uint256 makerFeeOffchainDelayedOrder;
        uint256 maxLeverage;
        uint256 maxMarketValue;
        uint256 maxFundingVelocity;
        uint256 skewScale;
        uint256 nextPriceConfirmWindow;
        uint256 delayedOrderConfirmWindow;
        uint256 minDelayTimeDelta;
        uint256 maxDelayTimeDelta;
        uint256 offchainDelayedOrderMinAge;
        uint256 offchainDelayedOrderMaxAge;
        bytes32 offchainMarketKey;
        uint256 offchainPriceDivergence;
    }

    function takerFee(bytes32 _marketKey) external view returns (uint256);

    function makerFee(bytes32 _marketKey) external view returns (uint256);

    function takerFeeDelayedOrder(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function makerFeeDelayedOrder(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function takerFeeOffchainDelayedOrder(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function makerFeeOffchainDelayedOrder(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function nextPriceConfirmWindow(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function delayedOrderConfirmWindow(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function offchainDelayedOrderMinAge(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function offchainDelayedOrderMaxAge(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function maxLeverage(bytes32 _marketKey) external view returns (uint256);

    function maxMarketValue(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function maxFundingVelocity(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function skewScale(bytes32 _marketKey) external view returns (uint256);

    function minDelayTimeDelta(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function maxDelayTimeDelta(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function parameters(bytes32 _marketKey)
        external
        view
        returns (Parameters memory);

    function offchainMarketKey(bytes32 _marketKey)
        external
        view
        returns (bytes32);

    function offchainPriceDivergence(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function minKeeperFee() external view returns (uint256);

    function liquidationFeeRatio() external view returns (uint256);

    function liquidationBufferRatio() external view returns (uint256);

    function minInitialMargin() external view returns (uint256);
}
