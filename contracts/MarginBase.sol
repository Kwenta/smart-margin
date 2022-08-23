// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";
import "./interfaces/IFuturesMarketManager.sol";
import "./interfaces/IMarginBaseTypes.sol";
import "./interfaces/IMarginBase.sol";
import "./utils/OpsReady.sol";
import "./utils/MinimalProxyable.sol";
import "./MarginBaseSettings.sol";

/// @title Kwenta MarginBase Account
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Flexible, minimalist, and gas-optimized cross-margin enabled account
/// for managing perpetual futures positions
contract MarginBase is MinimalProxyable, IMarginBase, OpsReady {
    /*///////////////////////////////////////////////////////////////
                                Constants
    ///////////////////////////////////////////////////////////////*/

    /// @notice tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    /// @notice name for futures market manager, needed for fetching market key
    bytes32 private constant FUTURES_MANAGER = "FuturesMarketManager";

    /// @notice max BPS
    uint256 private constant MAX_BPS = 10000;

    /// @notice constant for sUSD currency key
    bytes32 private constant SUSD = "sUSD";

    /*///////////////////////////////////////////////////////////////
                                State
    ///////////////////////////////////////////////////////////////*/

    // @notice synthetix address resolver
    IAddressResolver private addressResolver;

    /// @notice synthetix futures market manager
    IFuturesMarketManager private futuresManager;

    /// @notice settings for MarginBase account
    MarginBaseSettings public marginBaseSettings;

    /// @notice token contract used for account margin
    IERC20 public marginAsset;

    /// @notice margin locked for future events (ie. limit orders)
    uint256 public committedMargin;

    /// @notice market keys that the account has active positions in
    bytes32[] public activeMarketKeys;

    /// @notice market keys mapped to active market positions
    mapping(bytes32 => ActiveMarketPosition) public activeMarketPositions;

    /// @notice limit orders
    mapping(uint256 => Order) public orders;

    /// @notice sequentially id orders
    uint256 public orderId;

    /*///////////////////////////////////////////////////////////////
                                Events
    ///////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful deposit
    /// @param user: the address that deposited into account
    /// @param amount: amount of marginAsset to deposit into marginBase account
    event Deposit(address indexed user, uint256 amount);

    /// @notice emitted after a successful withdrawal
    /// @param user: the address that withdrew from account
    /// @param amount: amount of marginAsset to withdraw from marginBase account
    event Withdraw(address indexed user, uint256 amount);

    /// @notice emitted when tokens are rescued from this contract
    /// @param token: address of token recovered
    /// @param amount: amount of token recovered
    event Rescued(address token, uint256 amount);

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    ///////////////////////////////////////////////////////////////*/

    /// @notice helpful modifier to check non-zero values
    /// @param value: value to check if zero
    modifier notZero(uint256 value, bytes32 valueName) {
        /// @notice value cannot be zero
        if (value == 0) {
            revert ValueCannotBeZero(valueName);
        }
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                Errors
    ///////////////////////////////////////////////////////////////*/

    /// @notice amount deposited/withdrawn into/from account cannot be zero
    /// @param valueName: name of the variable that cannot be zero
    error ValueCannotBeZero(bytes32 valueName);

    /// @notice position with given marketKey does not exist
    /// @param marketKey: key for synthetix futures market
    error MissingMarketKey(bytes32 marketKey);

    /// @notice limit size of new position specs passed into distribute margin
    /// @param numberOfNewPositions: number of new position specs
    error MaxNewPositionsExceeded(uint256 numberOfNewPositions);

    /// @notice exceeds useable margin
    /// @param available: amount of useable margin asset
    /// @param required: amount of margin asset required
    error InsufficientFreeMargin(uint256 available, uint256 required);

    /// @notice cannot execute invalid order
    error OrderInvalid();

    /// @notice call to transfer ETH on withdrawal fails
    error EthWithdrawalFailed();

    /// @notice base price from the oracle was invalid
    /// @dev Rate can be invalid either due to:
    ///      1. Returned as invalid from ExchangeRates - due to being stale or flagged by oracle
    ///      2. Out of deviation bounds w.r.t. to previously stored rate
    ///      3. if there is no valid stored rate, w.r.t. to previous 3 oracle rates
    ///      4. Price is zero
    error InvalidPrice();

    /// @notice cannot rescue underlying margin asset token
    error CannotRescueMarginAsset();

    /*///////////////////////////////////////////////////////////////
                        Constructor & Initializer
    ///////////////////////////////////////////////////////////////*/

    /// @notice constructor never used except for first CREATE
    // solhint-disable-next-line
    constructor() MinimalProxyable() {}

    /// @notice initialize contract (only once) and transfer ownership to caller
    /// @dev ensure resolver and sUSD addresses are set to their proxies and not implementations
    /// @param _marginAsset: token contract address used for account margin
    /// @param _addressResolver: contract address for synthetix address resolver
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
        futuresManager = IFuturesMarketManager(
            addressResolver.requireAndGetAddress(
                FUTURES_MANAGER,
                "MarginBase: Could not get Futures Market Manager"
            )
        );
        marginAsset = IERC20(_marginAsset);

        /// @dev MarginBaseSettings must exist prior to MarginBase account creation
        marginBaseSettings = MarginBaseSettings(_marginBaseSettings);

        /// @dev the Ownable constructor is never called when we create minimal proxies
        _transferOwnership(msg.sender);

        ops = _ops;
    }

    /*///////////////////////////////////////////////////////////////
                                Views
    ///////////////////////////////////////////////////////////////*/

    /// @notice get number of active market positions account has
    /// @return number of positions which are currently active for account
    function getNumberOfActivePositions() external view returns (uint256) {
        return activeMarketKeys.length;
    }

    /// @notice get all active market positions
    /// @return positions which are currently active for account (ActiveMarketPosition structs)
    function getAllActiveMarketPositions()
        external
        view
        returns (ActiveMarketPosition[] memory)
    {
        ActiveMarketPosition[] memory positions = new ActiveMarketPosition[](
            activeMarketKeys.length
        );

        // there should never be more than 65535 activeMarketKeys
        for (uint16 i = 0; i < activeMarketKeys.length; i++) {
            positions[i] = (activeMarketPositions[activeMarketKeys[i]]);
        }

        return positions;
    }

    /// @notice the current withdrawable or usable balance
    function freeMargin() public view returns (uint256) {
        return marginAsset.balanceOf(address(this)) - committedMargin;
    }

    /*///////////////////////////////////////////////////////////////
                        Account Deposit & Withdraw
    ///////////////////////////////////////////////////////////////*/

    /// @param _amount: amount of marginAsset to deposit into marginBase account
    function deposit(uint256 _amount)
        public
        notZero(_amount, "_amount")
        onlyOwner
    {
        // transfer in margin asset from user
        // (will revert if user does not have amount specified)
        require(
            marginAsset.transferFrom(owner(), address(this), _amount),
            "MarginBase: deposit failed"
        );

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

        // transfer out margin asset to user
        // (will revert if account does not have amount specified)
        require(
            marginAsset.transfer(owner(), _amount),
            "MarginBase: withdraw failed"
        );

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice allow users to withdraw ETH deposited for keeper fees
    /// @param _amount: amount to withdraw
    function withdrawEth(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: _amount}("");
        if (!success) {
            revert EthWithdrawalFailed();
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Margin Distribution
    ///////////////////////////////////////////////////////////////*/

    /// @notice distribute margin across all/some positions specified via _newPositions
    /// @dev _newPositions may contain any number of new or existing positions
    /// @dev close and withdraw all margin from position if resulting position size is zero post trade
    /// @param _newPositions: an array of UpdateMarketPositionSpec's used to modify active market positions
    function distributeMargin(UpdateMarketPositionSpec[] memory _newPositions)
        external
        onlyOwner
    {
        _distributeMargin(_newPositions);
    }

    function _distributeMargin(UpdateMarketPositionSpec[] memory _newPositions)
        internal
    {
        /// @notice limit size of new position specs passed into distribute margin
        if (_newPositions.length > type(uint8).max) {
            revert MaxNewPositionsExceeded(_newPositions.length);
        }

        /// @notice tracking variable for calculating fee(s)
        uint256 totalSizeDeltaInUSD = 0;

        // for each new position in _newPositions, distribute margin accordingly and update state
        for (uint8 i = 0; i < _newPositions.length; i++) {
            // define market via _marketKey
            IFuturesMarket market = futuresMarket(_newPositions[i].marketKey);

            if (_newPositions[i].marginDelta < 0) {
                /// @notice remove margin from market and potentially adjust position size
                totalSizeDeltaInUSD += modifyPositionForMarketAndWithdraw(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey,
                    market
                );
            } else if (_newPositions[i].marginDelta > 0) {
                /// @notice deposit margin into market and potentially adjust position size
                totalSizeDeltaInUSD += depositAndModifyPositionForMarket(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey,
                    market
                );
            } else if (_newPositions[i].sizeDelta != 0) {
                /// @notice adjust position size
                /// @notice no margin deposited nor withdrawn from market
                totalSizeDeltaInUSD += modifyPositionForMarket(
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey,
                    market
                );
            }
        }

        /// @notice impose fee
        /// @dev send fee to Kwenta's treasury
        if (totalSizeDeltaInUSD > 0) {
            require(
                marginAsset.transfer(
                    marginBaseSettings.treasury(),
                    (totalSizeDeltaInUSD * marginBaseSettings.tradeFee()) /
                        MAX_BPS
                ),
                "MarginBase: unable to pay fee"
            );
        }
    }

    /// @notice accept a deposit amount and open new
    /// futures market position(s) all in a single tx
    /// @param _amount: amount of marginAsset to deposit into marginBase account
    /// @param _newPositions: an array of UpdateMarketPositionSpec's used to modify active market positions
    function depositAndDistribute(
        uint256 _amount,
        UpdateMarketPositionSpec[] memory _newPositions
    ) external onlyOwner {
        deposit(_amount);
        _distributeMargin(_newPositions);
    }

    /*///////////////////////////////////////////////////////////////
                    Internal Margin Distribution
    ///////////////////////////////////////////////////////////////*/

    /// @notice modify market position's size
    /// @dev _sizeDelta will always be non-zero
    /// @param _sizeDelta: size and position type (long/short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function modifyPositionForMarket(
        int256 _sizeDelta,
        bytes32 _marketKey,
        IFuturesMarket _market
    ) internal returns (uint256 sizeDeltaInUSD) {
        /// @notice _sizeDelta is measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        sizeDeltaInUSD = (sUSDRate(_market) * _abs(_sizeDelta)) / 1e18;

        // modify position in specific market with KWENTA tracking code
        _market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);

        /// @notice execute necessary state updates
        /// @dev must come after modifyPositionWithTracking() due to reliance on fetching
        /// futures market data from Synthetix to update interal state
        fetchPositionAndUpdate(_marketKey, _market);
    }

    /// @notice deposit margin into specific market and potentially modify position size
    /// @dev _depositSize will always be greater than zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long/short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        bytes32 _marketKey,
        IFuturesMarket _market
    ) internal returns (uint256 sizeDeltaInUSD) {
        /// @dev ensure trade doesn't spend margin which is not available
        uint256 absDepositSize = _abs(_depositSize);
        if (absDepositSize > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), absDepositSize);
        }

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        _market.transferMargin(_depositSize);

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            /// @notice _sizeDelta is measured in the underlying base asset of the market
            /// @dev fee will be measured in sUSD, thus exchange rate is needed
            sizeDeltaInUSD = (sUSDRate(_market) * _abs(_sizeDelta)) / 1e18;

            // modify position in specific market with KWENTA tracking code
            _market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        /// @notice execute necessary state updates
        /// @dev must come after modifyPositionWithTracking() due to reliance on fetching
        /// futures market data from Synthetix to update interal state
        fetchPositionAndUpdate(_marketKey, _market);
    }

    /// @notice potentially modify position size and withdraw margin from market
    /// @dev _withdrawalSize can NEVER be positive NOR zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _withdrawalSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawalSize,
        int256 _sizeDelta,
        bytes32 _marketKey,
        IFuturesMarket _market
    ) internal returns (uint256 sizeDeltaInUSD) {
        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            /// @notice _sizeDelta is measured in the underlying base asset of the market
            /// @dev fee will be measured in sUSD, thus exchange rate is needed
            sizeDeltaInUSD = (sUSDRate(_market) * _abs(_sizeDelta)) / 1e18;

            // modify position in specific market with KWENTA tracking code
            _market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        _market.transferMargin(_withdrawalSize);

        /// @notice execute necessary state updates
        /// @dev must come after modifyPositionWithTracking() due to reliance on fetching
        /// futures market data from Synthetix to update interal state
        fetchPositionAndUpdate(_marketKey, _market);
    }

    /// @notice fetch new position from Synthetix and update internal state
    /// @dev if position size is zero, function will close position
    /// @param _marketKey: synthetix futures market id/key
    /// @param _market: synthetix futures market
    function fetchPositionAndUpdate(bytes32 _marketKey, IFuturesMarket _market)
        internal
    {
        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = _market.positions(address(this));

        // if position size is 0, position is effectively closed on
        // FuturesMarket but margin is still in contract, thus it must
        // be withdrawn back to this account
        if (size == 0) {
            /// @dev closePositionAndWithdraw() will update internal state
            closePositionAndWithdraw(_marketKey, _market);

            // no need to proceed in function; early exit.
            return;
        }

        // update internal state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size);
    }

    /// @notice closes futures position and withdraws all margin in that market back to this account
    /// @param _marketKey: synthetix futures market id/key
    /// @param _market: synthetix futures market
    function closePositionAndWithdraw(
        bytes32 _marketKey,
        IFuturesMarket _market
    ) internal {
        // internally update state (remove market)
        removeActiveMarketPositon(_marketKey);

        // withdraw margin back to this account
        _market.withdrawAllMargin();
    }

    /*///////////////////////////////////////////////////////////////
                    Internal Account State Management
    ///////////////////////////////////////////////////////////////*/

    /// @notice used internally to update contract state for the account's active position tracking
    /// @dev parameters are generated and passed to this function via Synthetix Futures' contracts
    /// @param _marketKey: key for synthetix futures market
    /// @param _margin: amount of margin the specific market position has
    /// @param _size: represents size of position (i.e. accounts for leverage)
    function updateActiveMarketPosition(
        bytes32 _marketKey,
        uint128 _margin,
        int128 _size
    ) internal {
        ActiveMarketPosition memory newPosition = ActiveMarketPosition({
            marketKey: _marketKey,
            margin: _margin,
            size: _size
        });

        // check if this is updating a position or creating one
        if (activeMarketPositions[_marketKey].marketKey == 0) {
            activeMarketKeys.push(_marketKey);
        }

        // update state of active market positions
        activeMarketPositions[_marketKey] = newPosition;
    }

    /// @notice used internally to remove active market position from contract's internal state
    /// @param _marketKey: key for previously active market position
    function removeActiveMarketPositon(bytes32 _marketKey) internal {
        // ensure active market exists
        if (activeMarketPositions[_marketKey].marketKey == 0) {
            revert MissingMarketKey(_marketKey);
        }

        delete activeMarketPositions[_marketKey];
        uint256 numberOfActiveMarkets = activeMarketKeys.length;

        // @TODO update logic to not use for-loop if possible
        for (uint16 i = 0; i < numberOfActiveMarkets; i++) {
            // once _marketKey is encountered, swap with
            // last element in array and exit for-loop
            if (activeMarketKeys[i] == _marketKey) {
                /// @dev effectively removes _marketKey from activeMarketKeys
                activeMarketKeys[i] = activeMarketKeys[
                    numberOfActiveMarkets - 1
                ];
                break;
            }
        }
        // remove last element now that it has been copied
        activeMarketKeys.pop();
    }

    /*///////////////////////////////////////////////////////////////
                            Limit Orders
    ///////////////////////////////////////////////////////////////*/

    /// @notice order logic condition checker
    /// @dev this is where order type logic checks are handled
    /// @param _orderId: key for an active order
    function validOrder(uint256 _orderId) public view returns (bool) {
        Order memory order = orders[_orderId];
        if (order.orderType == OrderTypes.LIMIT) {
            return validLimitOrder(order);
        } else if (order.orderType == OrderTypes.STOP) {
            return validStopOrder(order);
        }
        // unknown order type
        return false;
    }

    /// @notice limit order logic condition checker
    /// @param order: struct for an active order
    function validLimitOrder(Order memory order) internal view returns (bool) {
        uint256 price = sUSDRate(futuresMarket(order.marketKey));

        /// @notice intent is targetPrice or better despite direction
        if (order.sizeDelta > 0) {
            // Long
            return price <= order.targetPrice;
        } else if (order.sizeDelta < 0) {
            // Short
            return price >= order.targetPrice;
        }

        // sizeDelta == 0
        return false;
    }

    /// @notice stop order logic condition checker
    /// @param order: struct for an active order
    function validStopOrder(Order memory order) internal view returns (bool) {
        uint256 price = sUSDRate(futuresMarket(order.marketKey));

        /// @notice intent is targetPrice or worse despite direction
        if (order.sizeDelta > 0) {
            // Long
            return price >= order.targetPrice;
        } else if (order.sizeDelta < 0) {
            // Short
            return price <= order.targetPrice;
        }

        // sizeDelta == 0
        return false;
    }

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _targetPrice: expected limit order price
    /// @param _orderType: expected order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @return orderId contract interface
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType
    )
        external
        payable
        notZero(_abs(_sizeDelta), "_sizeDelta")
        onlyOwner
        returns (uint256)
    {
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
            orderType: _orderType
        });

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
    }

    /// @notice execute a gelato queued order
    /// @notice only keepers can trigger this function
    /// @param _orderId: key for an active order
    function executeOrder(uint256 _orderId) external onlyOps {
        if (!validOrder(_orderId)) {
            revert OrderInvalid();
        }
        Order memory order = orders[_orderId];

        // if margin was committed, free it
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }

        // prep new position
        MarginBase.UpdateMarketPositionSpec[]
            memory newPositions = new MarginBase.UpdateMarketPositionSpec[](1);
        newPositions[0] = UpdateMarketPositionSpec({
            marketKey: order.marketKey,
            marginDelta: order.marginDelta,
            sizeDelta: order.sizeDelta
        });

        // delete order from orders
        delete orders[_orderId];

        // execute trade
        _distributeMargin(newPositions);

        // pay fee
        (uint256 fee, address feeToken) = IOps(ops).getFeeDetails();
        _transfer(fee, feeToken);
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
        canExec = validOrder(_orderId);
        // calldata for execute func
        execPayload = abi.encodeWithSelector(
            this.executeOrder.selector,
            _orderId
        );
    }

    /*///////////////////////////////////////////////////////////////
                        Internal Getter Utilities
    ///////////////////////////////////////////////////////////////*/

    /// @notice addressResolver fetches IFuturesMarket address for specific market
    /// @param _marketKey: key for synthetix futures market
    /// @return IFuturesMarket contract interface
    function futuresMarket(bytes32 _marketKey)
        internal
        view
        returns (IFuturesMarket)
    {
        return IFuturesMarket(futuresManager.marketForKey(_marketKey));
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param market: synthetix futures market
    /// @return price in sUSD
    function sUSDRate(IFuturesMarket market) internal view returns (uint256) {
        (uint256 price, bool invalid) = market.assetPrice();
        if (invalid) {
            revert InvalidPrice();
        }
        return price;
    }

    /*///////////////////////////////////////////////////////////////
                            Utility Functions
    ///////////////////////////////////////////////////////////////*/

    /// @notice Absolute value of the input, returned as an unsigned number.
    /// @param x: signed number
    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }

    /// @notice added to support recovering trapped erc20 tokens
    /// @param tokenAddress: address of token to be recovered
    /// @param tokenAmount: amount of token to be recovered
    function rescueERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        if (tokenAddress == address(marginAsset)) {
            revert CannotRescueMarginAsset();
        }
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
        emit Rescued(tokenAddress, tokenAmount);
    }
}
