// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@synthetix/IAddressResolver.sol";
import "@synthetix/IExchanger.sol";
import "@synthetix/IFuturesMarketManager.sol";
import "./interfaces/IMarginBaseTypes.sol";
import "./interfaces/IMarginBase.sol";
import "./interfaces/IMarginBaseSettings.sol";
import "./utils/MinimalProxyable.sol";
import "./utils/OpsReady.sol";

/// @title Kwenta MarginBase Account
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Flexible, minimalist, and gas-optimized cross-margin enabled account
/// for managing perpetual futures positions
contract MarginBase is MinimalProxyable, IMarginBase, OpsReady {
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    /// @notice name for futures market manager
    bytes32 private constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";

    /// @notice max BPS; used for decimals calculations
    uint256 private constant MAX_BPS = 10000;

    /// @notice constant for sUSD currency key
    bytes32 private constant SUSD = "sUSD";

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // @notice Synthetix address resolver
    IAddressResolver public addressResolver;

    /// @notice Synthetix futures market manager
    /// @dev responsible for storing all registered markets and provides overview
    /// views to get market summaries. MarginBase uses this to fetch for deployed market addresses
    IFuturesMarketManager public futuresMarketManager;

    /// @notice native settings for MarginBase account
    IMarginBaseSettings public marginBaseSettings;

    /// @notice token contract used for account margin
    IERC20 public marginAsset;

    /// @notice margin locked for future events (ie. limit orders)
    uint256 public committedMargin;

    /// @notice limit orders
    mapping(uint256 => Order) public orders;

    /// @notice sequentially id orders
    uint256 public orderId;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice helpful modifier to check non-zero values
    /// @param value: value to check if zero
    modifier notZero(uint256 value, bytes32 valueName) {
        /// @notice value cannot be zero
        if (value == 0) {
            revert ValueCannotBeZero(valueName);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice constructor never used except for first CREATE
    constructor() MinimalProxyable() {}

    /// @notice allows ETH to be deposited directly into a margin account
    /// @notice ETH can be withdrawn
    receive() external payable onlyOwner {}

    /// @notice initialize contract (only once) and transfer ownership to caller
    /// @dev ensure resolver and sUSD addresses are set to their proxies and not implementations
    /// @param _marginAsset: token contract address used for account margin
    /// @param _addressResolver: contract address for Synthetix address resolver
    /// @param _marginBaseSettings: contract address for MarginBase account settings
    /// @param _ops: gelato ops address
    function initialize(
        address _marginAsset,
        address _addressResolver,
        address _marginBaseSettings,
        address payable _ops
    ) external initOnce {
        marginAsset = IERC20(_marginAsset);
        addressResolver = IAddressResolver(_addressResolver);
        futuresMarketManager = IFuturesMarketManager(
            addressResolver.requireAndGetAddress(
                FUTURES_MARKET_MANAGER,
                "MarginBase: Could not get Futures Market Manager"
            )
        );

        /// @dev MarginBaseSettings must exist prior to MarginBase account creation
        marginBaseSettings = IMarginBaseSettings(_marginBaseSettings);

        /// @dev the Ownable constructor is never called when we create minimal proxies
        _transferOwnership(msg.sender);

        // set Gelato's ops address to create/remove tasks
        ops = _ops;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice the current withdrawable or usable balance
    function freeMargin() public view returns (uint256) {
        return marginAsset.balanceOf(address(this)) - committedMargin;
    }

    /// @notice get up-to-date position data from Synthetix PerpsV2
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return position struct defining current position
    function getPosition(bytes32 _marketKey)
        public
        view
        returns (IPerpsV2MarketConsolidated.Position memory position)
    {
        // fetch position data from Synthetix
        position = getPerpsV2Market(_marketKey).positions(address(this));
    }

    /// @notice get delayed order data from Synthetix PerpsV2
    /// @param _marketKey: key for Synthetix PerpsV2 Market
    /// @return order struct defining delayed order
    function getDelayedOrder(bytes32 _marketKey)
        public
        view
        returns (IPerpsV2MarketConsolidated.DelayedOrder memory order)
    {
        // fetch delayed order data from Synthetix
        order = getPerpsV2Market(_marketKey).delayedOrders(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNT DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit margin asset to trade with into this contract
    /// @param _amount: amount of marginAsset to deposit into marginBase account
    function deposit(uint256 _amount) public onlyOwner {
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) internal notZero(_amount, "_amount") {
        // attempt to transfer margin asset from user into this account
        bool success = marginAsset.transferFrom(
            owner(),
            address(this),
            _amount
        );
        if (!success) revert FailedMarginTransfer();

        emit Deposit(msg.sender, _amount);
    }

    /// @param _amount: amount of marginAsset to withdraw from marginBase account
    function withdraw(uint256 _amount)
        external
        notZero(_amount, "_amount")
        onlyOwner
    {
        // make sure committed margin isn't withdrawn
        if (_amount > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), _amount);
        }

        // attempt to transfer margin asset from this account to the user
        bool success = marginAsset.transfer(owner(), _amount);
        if (!success) revert FailedMarginTransfer();

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice allow users to withdraw ETH deposited for keeper fees
    /// @param _amount: amount to withdraw
    function withdrawEth(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: _amount}("");
        if (!success) revert EthWithdrawalFailed();
    }

    /*//////////////////////////////////////////////////////////////
                          MARGIN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice accept a deposit amount and open new
    /// Synthetix PerpsV2 Market position(s) all in a single tx
    /// @param _amount: amount of marginAsset to deposit into marginBase account
    /// @param _newPositions: an array of NewPosition's used to modify active market positions
    function depositAndDistribute(
        uint256 _amount,
        NewPosition[] memory _newPositions
    ) external onlyOwner {
        _deposit(_amount);
        _distributeMargin(_newPositions, 0);
    }

    /// @notice distribute margin across all/some positions specified via _newPositions
    /// @dev _newPositions may contain any number of new or existing positions
    /// @dev close and withdraw all margin from position if resulting position size is zero post trade
    /// @param _newPositions: an array of NewPosition's used to modify active market positions
    function distributeMargin(NewPosition[] memory _newPositions)
        external
        onlyOwner
    {
        _distributeMargin(_newPositions, 0);
    }

    
    function _distributeMargin(
        NewPosition[] memory _newPositions,
        uint256 _advancedOrderFee
    ) internal {
        /// @notice tracking variable for calculating trading fee(s)
        uint256 tradingFee = 0;

        // store length of new positions in memory
        uint256 newPositionsLength = _newPositions.length;

        // for each new position in _newPositions, distribute margin accordingly
        for (uint256 i = newPositionsLength; i != 0; ) {
            unchecked {
                --i;
            }

            // define market params to be used to create or modify a position
            bytes32 marketKey = _newPositions[i].marketKey;
            int256 sizeDelta = _newPositions[i].sizeDelta;
            int256 marginDelta = _newPositions[i].marginDelta;
            uint256 priceImpactDelta = _newPositions[i].priceImpactDelta;

            // define market
            IPerpsV2MarketConsolidated market = getPerpsV2Market(marketKey);

            // fetch position size from Synthetix
            int128 size = getPosition(marketKey).size;

            // if size is zero, then trade must specify non-zero sizeDelta
            if (size == 0 && sizeDelta == 0) {
                revert ValueCannotBeZero("sizeDelta");
            }

            // if this trade results in zero size,
            // close position and withdraw all margin from market
            if (size + sizeDelta == 0) {
                // close position and withdraw margin
                market.closePositionWithTracking({
                    priceImpactDelta: priceImpactDelta,
                    trackingCode: TRACKING_CODE
                });
                market.withdrawAllMargin();

                // determine trade fee based on size delta
                tradingFee += calculateTradeFee(
                    sizeDelta,
                    market,
                    _advancedOrderFee
                );

                // continue to next newPosition
                continue;
            }

            /// @notice submit trade
            /// @dev following trades will not result in position being closed
            /// @dev following trades may either modify or create a position
            if (marginDelta < 0) {
                // remove margin from market and potentially adjust position size
                tradingFee += modifyPositionForMarketAndWithdraw(
                    marginDelta,
                    sizeDelta,
                    market,
                    _advancedOrderFee,
                    priceImpactDelta
                );
            } else if (marginDelta > 0) {
                // deposit margin into market and potentially adjust position size
                tradingFee += depositAndModifyPositionForMarket(
                    marginDelta,
                    sizeDelta,
                    market,
                    _advancedOrderFee,
                    priceImpactDelta
                );
            } else if (sizeDelta != 0) {
                /// @notice adjust position size
                /// @notice no margin deposited nor withdrawn from market
                tradingFee += modifyPositionForMarket(
                    sizeDelta,
                    market,
                    _advancedOrderFee,
                    priceImpactDelta
                );
            }
        }

        /// @notice impose fee
        /// @dev send fee to Kwenta's treasury
        if (tradingFee > 0) {
            // fee canot be greater than available margin
            if (tradingFee > freeMargin()) {
                revert CannotPayFee();
            }

            // attempt to transfer margin asset from user to Kwenta's treasury
            bool success = marginAsset.transfer(
                marginBaseSettings.treasury(),
                tradingFee
            );
            if (!success) revert FailedMarginTransfer();

            emit FeeImposed(address(this), tradingFee);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             SUBMIT ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice modify market position's size
    /// @dev _sizeDelta will always be non-zero
    /// @param _sizeDelta: size and position type (long/short) denominated in market synth
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _advancedOrderFee: if additional fee charged for advanced orders
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @return fee *in sUSD*
    function modifyPositionForMarket(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee,
        uint256 _priceImpactDelta
    ) internal returns (uint256 fee) {
        // modify position in specific market with KWENTA tracking code
        _market.submitOffchainDelayedOrderWithTracking({
            sizeDelta: _sizeDelta,
            priceImpactDelta: _priceImpactDelta,
            trackingCode: TRACKING_CODE
        });

        // determine trade fee based on size delta
        fee = calculateTradeFee(_sizeDelta, _market, _advancedOrderFee);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        _market.transferMargin(int256(fee) * -1);
    }

    /// @notice deposit margin into specific market and potentially modify position size
    /// @dev _depositSize will always be greater than zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long/short) denominated in market synth
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _advancedOrderFee: if additional fee charged for advanced orders
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @return fee *in sUSD*
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee,
        uint256 _priceImpactDelta
    ) internal returns (uint256 fee) {
        /// @dev ensure trade doesn't spend margin which is not available
        uint256 absDepositSize = _abs(_depositSize);
        if (absDepositSize > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), absDepositSize);
        }

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // determine trade fee based on size delta
            fee = calculateTradeFee(_sizeDelta, _market, _advancedOrderFee);

            /// @notice alter the amount of margin in specific market position
            /// @dev positive input triggers a deposit; a negative one, a withdrawal
            /// @dev subtracting fee ensures margin account has enough margin to pay
            /// the fee (i.e. effectively fee comes from position)
            _market.transferMargin(_depositSize - int256(fee));

            // modify position in specific market with KWENTA tracking code
            _market.submitOffchainDelayedOrderWithTracking({
                sizeDelta: _sizeDelta,
                priceImpactDelta: _priceImpactDelta,
                trackingCode: TRACKING_CODE
            });
        } else {
            /// @notice alter the amount of margin in specific market position
            /// @dev positive input triggers a deposit; a negative one, a withdrawal
            _market.transferMargin(_depositSize);
        }
    }

    /// @notice potentially modify position size and withdraw margin from market
    /// @dev _withdrawalSize will always be less than zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _withdrawalSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denominated in market synth
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _advancedOrderFee: if additional fee charged for advanced orders
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @return fee *in sUSD*
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawalSize,
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee,
        uint256 _priceImpactDelta
    ) internal returns (uint256 fee) {
        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // modify position in specific market with KWENTA tracking code
            _market.submitOffchainDelayedOrderWithTracking({
                sizeDelta: _sizeDelta,
                priceImpactDelta: _priceImpactDelta,
                trackingCode: TRACKING_CODE
            });

            // determine trade fee based on size delta
            fee = calculateTradeFee(_sizeDelta, _market, _advancedOrderFee);

            /// @notice alter the amount of margin in specific market position
            /// @dev positive input triggers a deposit; a negative one, a withdrawal
            /// @dev subtracting fee ensures margin account has enough margin to pay
            /// the fee (i.e. effectively fee comes from position)
            _market.transferMargin(_withdrawalSize - int256(fee));
        } else {
            /// @notice alter the amount of margin in specific market position
            /// @dev positive input triggers a deposit; a negative one, a withdrawal
            _market.transferMargin(_withdrawalSize);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEE CALCULATION
    //////////////////////////////////////////////////////////////*/

    /// @notice calculate fee based on both size and given market
    /// @param _sizeDelta: size delta of given trade
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _advancedOrderFee: additional fee charged for advanced orders
    /// @dev _advancedOrderFee will be zero if trade is not an advanced order
    /// @return fee to be imposed based on size delta
    function calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee
    ) internal view returns (uint256 fee) {
        fee =
            (_abs(_sizeDelta) *
                (marginBaseSettings.tradeFee() + _advancedOrderFee)) /
            MAX_BPS;
        /// @notice fee is currently measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        fee = (sUSDRate(_market) * fee) / 1e18;
    }

    /*//////////////////////////////////////////////////////////////
                            ADVANCED ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice order logic condition checker
    /// @dev this is where order type logic checks are handled
    /// @param _orderId: key for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be filled at (only valid if prev is true)
    function validOrder(uint256 _orderId) public view returns (bool, uint256) {
        Order memory order = orders[_orderId];

        if (order.maxDynamicFee != 0) {
            (uint256 dynamicFee, bool tooVolatile) = exchanger()
                .dynamicFeeRateForExchange(
                    SUSD,
                    getPerpsV2Market(order.marketKey).baseAsset()
                );
            if (tooVolatile || dynamicFee > order.maxDynamicFee) {
                return (false, 0);
            }
        }

        if (order.orderType == OrderTypes.LIMIT) {
            return validLimitOrder(order);
        } else if (order.orderType == OrderTypes.STOP) {
            return validStopOrder(order);
        }

        // unknown order type
        // @notice execution should never reach here
        // @dev needed to satisfy types
        return (false, 0);
    }

    /// @notice limit order logic condition checker
    /// @param order: struct for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be filled at (only valid if prev is true)
    function validLimitOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));

        /// @notice intent is targetPrice or better despite direction
        if (order.sizeDelta > 0) {
            // Long
            return (price <= order.targetPrice, price);
        } else if (order.sizeDelta < 0) {
            // Short
            return (price >= order.targetPrice, price);
        }

        // sizeDelta == 0
        // @notice execution should never reach here
        // @dev needed to satisfy types
        return (false, price);
    }

    /// @notice stop order logic condition checker
    /// @param order: struct for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be filled at (only valid if prev is true)
    function validStopOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));

        /// @notice intent is targetPrice or worse despite direction
        if (order.sizeDelta > 0) {
            // Long
            return (price >= order.targetPrice, price);
        } else if (order.sizeDelta < 0) {
            // Short
            return (price <= order.targetPrice, price);
        }

        // sizeDelta == 0
        // @notice execution should never reach here
        // @dev needed to satisfy types
        return (false, price);
    }

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _targetPrice: expected limit order price
    /// @param _orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @return orderId contract interface
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta
    ) external payable returns (uint256) {
        return
            _placeOrder({
                _marketKey: _marketKey,
                _marginDelta: _marginDelta,
                _sizeDelta: _sizeDelta,
                _targetPrice: _targetPrice,
                _orderType: _orderType,
                _priceImpactDelta: _priceImpactDelta,
                _maxDynamicFee: 0
            });
    }

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _targetPrice: expected limit order price
    /// @param _orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _priceImpactDelta: price impact tolerance as a percentage
    /// @param _maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    /// @return orderId contract interface
    function placeOrderWithFeeCap(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta,
        uint256 _maxDynamicFee
    ) external payable returns (uint256) {
        return
            _placeOrder({
                _marketKey: _marketKey,
                _marginDelta: _marginDelta,
                _sizeDelta: _sizeDelta,
                _targetPrice: _targetPrice,
                _orderType: _orderType,
                _priceImpactDelta: _priceImpactDelta,
                _maxDynamicFee: _maxDynamicFee
            });
    }

    function _placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta,
        uint256 _maxDynamicFee
    )
        internal
        notZero(_abs(_sizeDelta), "_sizeDelta")
        onlyOwner
        returns (uint256)
    {
        if (address(this).balance < 1 ether / 100) {
            revert InsufficientEthBalance(address(this).balance, 1 ether / 100);
        }
        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            // ensure margin doesn't exceed max
            if (_abs(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), _abs(_marginDelta));
            }
            committedMargin += _abs(_marginDelta);
        }

        bytes32 taskId = IOps(ops).createTaskNoPrepayment(
            address(this), // execution function address
            this.executeOrder.selector, // execution function selector
            address(this), // checker (resolver) address
            abi.encodeWithSelector(this.checker.selector, orderId), // checker (resolver) calldata
            ETH // payment token
        );

        orders[orderId] = Order({
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            gelatoTaskId: taskId,
            orderType: _orderType,
            priceImpactDelta: _priceImpactDelta,
            maxDynamicFee: _maxDynamicFee
        });

        emit OrderPlaced(
            address(this),
            orderId,
            _marketKey,
            _marginDelta,
            _sizeDelta,
            _targetPrice,
            _orderType,
            _priceImpactDelta,
            _maxDynamicFee
        );

        return orderId++;
    }

    /// @notice cancel a gelato queued order
    /// @param _orderId: key for an active order
    function cancelOrder(uint256 _orderId) external onlyOwner {
        Order memory order = orders[_orderId];

        // if margin was committed, free it
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }
        IOps(ops).cancelTask(order.gelatoTaskId);

        // delete order from orders
        delete orders[_orderId];

        emit OrderCancelled(address(this), _orderId);
    }

    /// @notice execute a gelato queued order
    /// @notice only keepers can trigger this function
    /// @param _orderId: key for an active order
    function executeOrder(uint256 _orderId) external onlyOps {
        (bool isValidOrder, uint256 fillPrice) = validOrder(_orderId);
        if (!isValidOrder) {
            revert OrderInvalid();
        }
        Order memory order = orders[_orderId];

        // if margin was committed, free it
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }

        // prep new position
        MarginBase.NewPosition[]
            memory newPositions = new MarginBase.NewPosition[](1);
        newPositions[0] = NewPosition({
            marketKey: order.marketKey,
            marginDelta: order.marginDelta,
            sizeDelta: order.sizeDelta,
            priceImpactDelta: order.priceImpactDelta
        });

        // remove task from gelato's side
        /// @dev optimization done for gelato
        IOps(ops).cancelTask(order.gelatoTaskId);

        // delete order from orders
        delete orders[_orderId];

        uint256 advancedOrderFee = order.orderType == OrderTypes.LIMIT
            ? marginBaseSettings.limitOrderFee()
            : marginBaseSettings.stopOrderFee();

        // execute trade
        _distributeMargin(newPositions, advancedOrderFee);

        // pay fee
        (uint256 fee, address feeToken) = IOps(ops).getFeeDetails();
        _transfer(fee, feeToken);

        emit OrderFilled(address(this), _orderId, fillPrice, fee);
    }

    /// @notice signal to a keeper that an order is valid/invalid for execution
    /// @param _orderId: key for an active order
    /// @return canExec boolean that signals to keeper an order can be executed
    /// @return execPayload calldata for executing an order
    function checker(uint256 _orderId)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        (canExec, ) = validOrder(_orderId);
        // calldata for execute func
        execPayload = abi.encodeWithSelector(
            this.executeOrder.selector,
            _orderId
        );
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice addressResolver fetches PerpsV2Market market defined by market key
    /// @param _marketKey: key for Synthetix PerpsV2 market
    /// @return IPerpsV2Market contract interface
    function getPerpsV2Market(bytes32 _marketKey)
        internal
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return
            IPerpsV2MarketConsolidated(
                futuresMarketManager.marketForKey(_marketKey)
            );
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param _market: Synthetix PerpsV2 Market
    /// @return price in sUSD
    function sUSDRate(IPerpsV2MarketConsolidated _market)
        internal
        view
        returns (uint256)
    {
        (uint256 price, bool invalid) = _market.assetPrice();
        if (invalid) {
            revert InvalidPrice();
        }
        return price;
    }

    /// @notice exchangeRates() fetches current ExchangeRates contract
    function exchanger() internal view returns (IExchanger) {
        return
            IExchanger(
                addressResolver.requireAndGetAddress(
                    "Exchanger",
                    "MarginBase: Could not get Exchanger"
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                             MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Absolute value of the input, returned as an unsigned number.
    /// @param x: signed number
    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
