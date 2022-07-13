// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";
import "./interfaces/IFuturesMarketManager.sol";
import "./interfaces/IExchangeRates.sol";
import "./utils/OpsReady.sol";
import "./utils/MinimalProxyable.sol";
import "./MarginBaseSettings.sol";

/// @title Kwenta MarginBase Account
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Flexible, minimalist, and gas-optimized cross-margin enabled account
/// for managing perpetual futures positions
contract MarginBase is MinimalProxyable, OpsReady {
    /*///////////////////////////////////////////////////////////////
                                Constants
    ///////////////////////////////////////////////////////////////*/

    /// @notice tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    /// @notice name for futures market manager, needed for fetching market key
    bytes32 private constant FUTURES_MANAGER = "FuturesMarketManager";

    /// @notice max BPS
    uint256 private constant MAX_BPS = 10000;

    // constant for sUSD currency key
    bytes32 private constant SUSD = "sUSD";

    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    // marketKey: synthetix futures market id/key
    // margin: amount of margin (in sUSD) in specific futures market
    // size: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    struct ActiveMarketPosition {
        bytes32 marketKey;
        uint128 margin;
        int128 size;
    }

    // marketKey: synthetix futures market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    // isClosing: indicates if position needs to be closed
    struct UpdateMarketPositionSpec {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
        bool isClosing; // if true, marginDelta nor sizeDelta are considered. simply closes position
    }

    // marketKey: synthetix futures market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    // desiredPrice: limit or stop price desired
    // gelatoTaskId: unqiue taskId from gelato necessary for cancelling orders
    struct Order {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
        uint256 desiredPrice;
        bytes32 gelatoTaskId;
    }

    /*///////////////////////////////////////////////////////////////
                                State
    ///////////////////////////////////////////////////////////////*/

    /// @notice settings for MarginBase account
    MarginBaseSettings public marginBaseSettings;

    /// @notice synthetix address resolver
    IAddressResolver private addressResolver;

    /// @notice synthetix futures market manager
    IFuturesMarketManager private futuresManager;

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

    /*///////////////////////////////////////////////////////////////
                                Errors
    ///////////////////////////////////////////////////////////////*/

    /// @notice amount deposited/withdrawn into/from account cannot be zero
    error AmountCantBeZero();

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

    /// @notice size cannot be zero when placing a limit/stop order
    error SizeCannotBeZero();

    /// @notice cannot execute invalid order
    error OrderInvalid();

    /// @notice call to transfer ETH on withdrawal fails
    error EthWithdrawalFailed();

    /*///////////////////////////////////////////////////////////////
                        Constructor & Initializer
    ///////////////////////////////////////////////////////////////*/

    /// @notice constructor never used except for first CREATE
    // solhint-disable-next-line
    constructor() MinimalProxyable() {}

    /// @notice initialize contract (only once) and transfer ownership to caller
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
    function deposit(uint256 _amount) external onlyOwner {
        /// @notice amount deposited into account cannot be zero
        if (_amount == 0) {
            revert AmountCantBeZero();
        }

        // transfer in margin asset from user
        // (will revert if user does not have amount specified)
        require(
            marginAsset.transferFrom(owner(), address(this), _amount),
            "MarginBase: deposit failed"
        );

        emit Deposit(msg.sender, _amount);
    }

    /// @param _amount: amount of marginAsset to withdraw from marginBase account
    function withdraw(uint256 _amount) external onlyOwner {
        /// @notice amount withdrawn from account cannot be zero
        if (_amount == 0) {
            revert AmountCantBeZero();
        }

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
    /// @dev caller can close and withdraw all margin from position if _newPositions[i].isClosing is true
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
        if (_newPositions.length > type(uint16).max) {
            revert MaxNewPositionsExceeded(_newPositions.length);
        }

        /// @notice tracking variable for calculating fee(s) based on margin delta
        /// @dev margin delta: total margin deposited/withdrawn across ALL new positions
        uint256 totalMarginDelta = 0;

        // for each new position in _newPositions, distribute margin accordingly and update state
        for (uint16 i = 0; i < _newPositions.length; i++) {
            if (_newPositions[i].isClosing) {
                /// @notice close position and transfer margin back to account
                totalMarginDelta += closePositionAndWithdraw(
                    _newPositions[i].marketKey
                );
            } else if (_newPositions[i].marginDelta < 0) {
                /// @notice remove margin from market and potentially adjust size
                totalMarginDelta += modifyPositionForMarketAndWithdraw(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey
                );
            } else {
                /// @dev marginDelta >= 0
                /// @notice deposit margin into market and potentially adjust size
                totalMarginDelta += depositAndModifyPositionForMarket(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey
                );
                // if marginDelta is 0, there will simply be NO additional
                // margin deposited into the market
            }
        }

        /// @notice impose fee: send fee to Kwenta's treasury IF margin was deposited/withdrawn
        if (totalMarginDelta > 0) {
            require(
                marginAsset.transfer(
                    marginBaseSettings.treasury(),
                    (totalMarginDelta * marginBaseSettings.distributionFee()) /
                        MAX_BPS
                ),
                "MarginBase: unable to pay fee"
            );
        }
    }

    // @TODO https://github.com/Kwenta/margin-manager/issues/12

    /*///////////////////////////////////////////////////////////////
                    Internal Margin Distribution
    ///////////////////////////////////////////////////////////////*/

    /// @notice deposit margin into specific market, creating/adding to a position
    /// @dev _depositSize can NEVER be negative
    /// @dev both _depositSize and _sizeDelta could be zero (i.e. market position goes unchanged)
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    /// @return marginMoved total margin moved in function call
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) internal returns (uint256 marginMoved) {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @dev if _depositSize is not 0, then we must:
        /// (1) impose correct fee
        /// (2) transfer _depositSize (new margin) into the market
        if (_depositSize > 0) {
            /// @notice marginMoved used to calculate fee based on _depositSize
            marginMoved = _abs(_depositSize);

            // make sure committed margin isn't deposited
            if (marginMoved > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), marginMoved);
            }

            /// @notice alter the amount of margin in specific market position
            /// @dev positive input triggers a deposit; a negative one, a withdrawal
            market.transferMargin(_depositSize);
        }

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // modify position in specific market with KWENTA tracking code
            market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        marginMoved += updateActiveMarketPosition(
            _marketKey,
            margin,
            size,
            market
        );
    }

    /// @notice modify active position and withdraw marginAsset from market into this account
    /// @dev _withdrawalSize can NEVER be positive NOR zero
    /// @dev _sizeDelta could be zero
    /// @param _withdrawalSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    /// @return marginMoved total margin moved in function call
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawalSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) internal returns (uint256 marginMoved) {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @notice marginMoved used to calculate fee based on _withdrawalSize
        marginMoved = _abs(_withdrawalSize);

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // modify position in specific market with KWENTA tracking code
            market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(_withdrawalSize);

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        marginMoved += updateActiveMarketPosition(
            _marketKey,
            margin,
            size,
            market
        );
    }

    /// @notice closes futures position and withdraws all margin in that market back to this account
    /// @param _marketKey: synthetix futures market id/key
    /// @return marginMoved total margin moved in function call
    function closePositionAndWithdraw(bytes32 _marketKey)
        internal
        returns (uint256 marginMoved)
    {
        // update state (remove market)
        removeActiveMarketPositon(_marketKey);

        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // close market position
        market.closePosition();

        // fetch position data from Synthetix
        (, , uint128 margin, , ) = market.positions(address(this));

        /// @notice marginMoved used to calculate fee based on margin in market being closed
        marginMoved = margin;

        // withdraw margin back to this account
        market.withdrawAllMargin();
    }

    /*///////////////////////////////////////////////////////////////
                    Internal Account State Management
    ///////////////////////////////////////////////////////////////*/

    /// @notice used internally to update contract state for the account's active position tracking
    /// @dev parameters are generated and passed to this function via Synthetix Futures' contracts
    /// @dev if _size becomes 0, remove position from account state and withdraw margin (only non-"internal" logic in below code)
    /// @param _marketKey: key for synthetix futures market
    /// @param _margin: amount of margin the specific market position has
    /// @param _size: represents size of position (i.e. accounts for leverage)
    /// @return marginMoved total margin moved in function call
    function updateActiveMarketPosition(
        bytes32 _marketKey,
        uint128 _margin,
        int128 _size,
        IFuturesMarket market
    ) internal returns (uint256 marginMoved) {
        // if position size is 0, position is effectively closed on
        // FuturesMarket but margin is still in contract, thus it must
        // be withdrawn back to this account
        if (_size == 0) {
            // update state (remove market)
            removeActiveMarketPositon(_marketKey);

            /// @notice marginMoved used to calculate fee based on margin in market being closed
            marginMoved = _margin;

            // withdraw margin back to this account
            market.withdrawAllMargin();
            return marginMoved;
        }

        ActiveMarketPosition memory newPosition = ActiveMarketPosition(
            _marketKey,
            _margin,
            _size
        );

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

    /// @notice exchangeRates() fetches current ExchangeRates contract
    function exchangeRates() internal view returns (IExchangeRates) {
        return
            IExchangeRates(
                addressResolver.requireAndGetAddress(
                    "ExchangeRates",
                    "MarginBase: Could not get ExchangeRates"
                )
            );
    }

    /*///////////////////////////////////////////////////////////////
                            Limit Orders
    ///////////////////////////////////////////////////////////////*/

    /// @notice limit order logic condition checker
    /// @param _orderId: key for an active order
    function validOrder(uint256 _orderId) public view returns (bool) {
        Order memory order = orders[_orderId];

        bytes32 currencyKey = futuresMarket(order.marketKey).baseAsset();
        // Get exchange rate for 1 unit
        uint256 price = exchangeRates().effectiveValue(currencyKey, 1e18, SUSD);

        if (order.sizeDelta > 0) {
            // Long
            return price <= order.desiredPrice;
        } else if (order.sizeDelta < 0) {
            // Short
            return price >= order.desiredPrice;
        }
    }

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _limitPrice: expected limit order price
    /// @return orderId contract interface
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _limitPrice
    ) external payable onlyOwner returns (uint256) {
        if (_sizeDelta == 0) {
            revert SizeCannotBeZero();
        }
        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            // ensure margin doesn't exceed max
            if (_abs(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), _abs(_marginDelta));
            }
            committedMargin += _abs(_marginDelta);
        }

        bytes32 taskId = IOps(ops).createTask(
            address(this), // execution function address
            this.executeOrder.selector, // execution function selector
            address(this), // checker (resolver) address
            abi.encodeWithSelector(this.checker.selector, orderId) // checker (resolver) calldata
        );

        orders[orderId] = Order({
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            desiredPrice: _limitPrice,
            gelatoTaskId: taskId
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
        newPositions[0] = MarginBase.UpdateMarketPositionSpec(
            order.marketKey,
            order.marginDelta,
            order.sizeDelta,
            false // assume the position will be closed if the limit order is the opposite size
        );

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
                    Utility Functions
    ///////////////////////////////////////////////////////////////*/

    /// @notice Absolute value of the input, returned as an unsigned number.
    /// @param x: signed number
    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
