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

    function expose_validConditionalOrder(uint256 _conditionalOrderId)
        external
        view
        returns (bool, uint256)
    {
        return (_validConditionalOrder(_conditionalOrderId));
    }

    /*//////////////////////////////////////////////////////////////
                            EXPOSED COMMANDS
    //////////////////////////////////////////////////////////////*/

    function expose_ACCOUNT_MODIFY_MARGIN(int256 amount) external {
        _modifyAccountMargin({_amount: amount});
    }

    function expose_ACCOUNT_WITHDRAW_ETH(uint256 amount) external {
        _withdrawEth({_amount: amount});
    }

    function expose_PERPS_V2_MODIFY_MARGIN(address market, int256 amount) external {
        _perpsV2ModifyMargin({_market: market, _amount: amount});
    }

    function expose_PERPS_V2_WITHDRAW_ALL_MARGIN(address market) external {
        _perpsV2WithdrawAllMargin({_market: market});
    }

    function expose_PERPS_V2_SUBMIT_ATOMIC_ORDER(
        address market,
        int256 sizeDelta,
        uint256 priceImpactDelta
    ) external {
        _perpsV2SubmitAtomicOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _priceImpactDelta: priceImpactDelta
        });
    }

    function expose_PERPS_V2_SUBMIT_DELAYED_ORDER(
        address market,
        int256 sizeDelta,
        uint256 priceImpactDelta,
        uint256 desiredTimeDelta
    ) external {
        _perpsV2SubmitDelayedOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _priceImpactDelta: priceImpactDelta,
            _desiredTimeDelta: desiredTimeDelta
        });
    }

    function expose_PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER(
        address market,
        int256 sizeDelta,
        uint256 priceImpactDelta
    ) external {
        _perpsV2SubmitOffchainDelayedOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _priceImpactDelta: priceImpactDelta
        });
    }

    function expose_PERPS_V2_CANCEL_DELAYED_ORDER(address market) external {
        _perpsV2CancelDelayedOrder({_market: market});
    }

    function expose_PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER(address market) external {
        _perpsV2CancelOffchainDelayedOrder({_market: market});
    }

    function expose_PERPS_V2_CLOSE_POSITION(address market, uint256 priceImpactDelta) external {
        _perpsV2ClosePosition({_market: market, _priceImpactDelta: priceImpactDelta});
    }

    function expose_GELATO_PLACE_CONDITIONAL_ORDER(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        ConditionalOrderTypes conditionalOrderType,
        uint128 priceImpactDelta,
        bool reduceOnly
    ) external {
        _placeConditionalOrder({
            _marketKey: marketKey,
            _marginDelta: marginDelta,
            _sizeDelta: sizeDelta,
            _targetPrice: targetPrice,
            _conditionalOrderType: conditionalOrderType,
            _priceImpactDelta: priceImpactDelta,
            _reduceOnly: reduceOnly
        });
    }

    function expose_GELATO_CANCEL_CONDITIONAL_ORDER(uint256 orderId) external {
        _cancelConditionalOrder({_conditionalOrderId: orderId});
    }
}
