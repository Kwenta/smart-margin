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

    /*//////////////////////////////////////////////////////////////
                            EXPOSED COMMANDS
    //////////////////////////////////////////////////////////////*/

    function expose_modifyAccountMargin(int256 amount) external {
        _modifyAccountMargin({_amount: amount});
    }

    function expose_withdrawEth(uint256 amount) external {
        _withdrawEth({_amount: amount});
    }

    function expose_perpsV2ModifyMargin(address market, int256 amount)
        external
    {
        _perpsV2ModifyMargin({_market: market, _amount: amount});
    }

    function expose_perpsV2WithdrawAllMargin(address market) external {
        _perpsV2WithdrawAllMargin({_market: market});
    }

    function expose_perpsV2SubmitAtomicOrder(
        address market,
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) external {
        _perpsV2SubmitAtomicOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _desiredFillPrice: desiredFillPrice
        });
    }

    function expose_perpsV2SubmitDelayedOrder(
        address market,
        int256 sizeDelta,
        uint256 desiredTimeDelta,
        uint256 desiredFillPrice
    ) external {
        _perpsV2SubmitDelayedOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _desiredTimeDelta: desiredTimeDelta,
            _desiredFillPrice: desiredFillPrice
        });
    }

    function expose_perpsV2SubmitOffchainDelayedOrder(
        address market,
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) external {
        _perpsV2SubmitOffchainDelayedOrder({
            _market: market,
            _sizeDelta: sizeDelta,
            _desiredFillPrice: desiredFillPrice
        });
    }

    function expose_perpsV2CancelDelayedOrder(address market) external {
        _perpsV2CancelDelayedOrder({_market: market});
    }

    function expose_perpsV2CancelOffchainDelayedOrder(address market)
        external
    {
        _perpsV2CancelOffchainDelayedOrder({_market: market});
    }

    function expose_PERPS_V2_CLOSE_POSITION(
        address market,
        uint256 desiredFillPrice
    ) external {
        _perpsV2ClosePosition({
            _market: market,
            _desiredFillPrice: desiredFillPrice
        });
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

    function expose_cancelConditionalOrder(uint256 orderId) external {
        _cancelConditionalOrder({_conditionalOrderId: orderId});
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

    function expose_validConditionalOrder(uint256 _conditionalOrderId)
        external
        view
        returns (bool)
    {
        return (_validConditionalOrder(_conditionalOrderId));
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
