// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {
    Account,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated,
    IEvents,
    IOps
} from "../../src/Account.sol";
import "./Constants.sol";

/// @dev This contract exposes the internal functions of Account.sol for testing purposes
contract AccountExposed is Account {
    constructor(
        address _factory,
        address _events,
        address _marginAsset,
        address _perpsV2ExchangeRate,
        address _futuresMarketManager,
        address _systemStatus,
        address _gelato,
        address _ops,
        address _settings
    )
        Account(
            _factory,
            _events,
            _marginAsset,
            _perpsV2ExchangeRate,
            _futuresMarketManager,
            _systemStatus,
            _gelato,
            _ops,
            _settings
        )
    {}

    function expose_TRACKING_CODE() public pure returns (bytes32) {
        return TRACKING_CODE;
    }

    function expose_FACTORY() public view returns (address) {
        return address(FACTORY);
    }

    function expose_EVENTS() public view returns (address) {
        return address(EVENTS);
    }

    function expose_MARGIN_ASSET() public view returns (address) {
        return address(MARGIN_ASSET);
    }

    function expose_PERPS_V2_EXCHANGE_RATE() public view returns (address) {
        return address(PERPS_V2_EXCHANGE_RATE);
    }

    function expose_FUTURES_MARKET_MANAGER() public view returns (address) {
        return address(FUTURES_MARKET_MANAGER);
    }

    function expose_SYSTEM_STATUS() public view returns (address) {
        return address(SYSTEM_STATUS);
    }

    function expose_GELATO() public view returns (address) {
        return address(GELATO);
    }

    function expose_OPS() public view returns (address) {
        return address(OPS);
    }

    function expose_placeConditionalOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        ConditionalOrderTypes conditionalOrderType,
        uint256 desiredFillPrice,
        bool reduceOnly
    ) external {
        _placeConditionalOrder({
            _marketKey: marketKey,
            _marginDelta: marginDelta,
            _sizeDelta: sizeDelta,
            _targetPrice: targetPrice,
            _conditionalOrderType: conditionalOrderType,
            _desiredFillPrice: desiredFillPrice,
            _reduceOnly: reduceOnly
        });
    }

    function expose_getPerpsV2Market(bytes32 _marketKey)
        public
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return _getPerpsV2Market(_marketKey);
    }

    function expose_sUSDRate(IPerpsV2MarketConsolidated _market)
        public
        view
        returns (uint256, PriceOracleUsed)
    {
        return _sUSDRate(_market);
    }

    function expose_abs(int256 x) public pure returns (uint256) {
        return _abs(x);
    }

    function expose_isSameSign(int256 x, int256 y) public pure returns (bool) {
        return _isSameSign(x, y);
    }
}
