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
        address _events,
        address _marginAsset,
        address _futuresMarketManager,
        address _systemStatus,
        address _gelato,
        address _ops
    )
        Account(
            _events,
            _marginAsset,
            _futuresMarketManager,
            _systemStatus,
            _gelato,
            _ops
        )
    {}

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

    /*//////////////////////////////////////////////////////////////
                        EXPOSED GETTER UTILITIES
    //////////////////////////////////////////////////////////////*/

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
        returns (uint256)
    {
        return _sUSDRate(_market);
    }

    /*//////////////////////////////////////////////////////////////
                         EXPOSED MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    function expose_abs(int256 x) public pure returns (uint256) {
        return _abs(x);
    }

    function expose_isSameSign(int256 x, int256 y) public pure returns (bool) {
        return _isSameSign(x, y);
    }
}
