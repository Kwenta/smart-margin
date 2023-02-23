// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {
    Account,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated,
    ISettings
} from "../../src/Account.sol";

/// @dev This contract exposes the internal functions of Account.sol for testing purposes
contract AccountExposed is Account {
    function setSettings(ISettings _settings) public {
        settings = _settings;
    }

    function setFuturesMarketManager(IFuturesMarketManager _futuresMarketManager) external {
        futuresMarketManager = _futuresMarketManager;
    }

    function expose_abs(int256 x) public pure returns (uint256) {
        return _abs(x);
    }

    function expose_isSameSign(int256 x, int256 y) public pure returns (bool) {
        return _isSameSign(x, y);
    }

    function expose_calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _conditionalOrderFee
    ) public view returns (uint256 fee) {
        return _calculateTradeFee(_sizeDelta, _market, _conditionalOrderFee);
    }

    function expose_sUSDRate(IPerpsV2MarketConsolidated _market) public view returns (uint256) {
        return _sUSDRate(_market);
    }

    function expose_getPerpsV2Market(bytes32 _marketKey)
        public
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return _getPerpsV2Market(_marketKey);
    }
}
