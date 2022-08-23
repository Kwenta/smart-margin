// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
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
    using BitMaps for BitMaps.BitMap;

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

    /// @notice active markets bitmap
    BitMaps.BitMap private markets;

    /// @notice market keys that the account has active positions in
    bytes32[] public activeMarketKeys;

    /// @notice active market keys mapped to index in activeMarketKeys
    mapping(bytes32 => uint256) public marketKeyIndex;

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

    /// @notice given value cannot be zero
    /// @param valueName: name of the variable that cannot be zero
    error ValueCannotBeZero(bytes32 valueName);

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

    /// @notice get number of internal market positions account has
    /// @return number of positions which are internally accounted for
    function getNumberOfInternalPositions() external view returns (uint256) {
        return activeMarketKeys.length;
    }

    /// @notice the current withdrawable or usable balance
    function freeMargin() public view returns (uint256) {
        return marginAsset.balanceOf(address(this)) - committedMargin;
    }

    /// @notice get up-to-date position data from Synthetix
    /// @param _marketKey: key for synthetix futures market
    function getPosition(bytes32 _marketKey)
        external
        view
        returns (
            uint64 id,
            uint64 fundingIndex,
            uint128 margin,
            uint128 lastPrice,
            int128 size
        )
    {
        // fetch position data from Synthetix
        (id, fundingIndex, margin, lastPrice, size) = futuresMarket(_marketKey)
            .positions(address(this));
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
        // solhint-disable-next-line
        (bool success, ) = payable(owner()).call{value: _amount}("");
        if (!success) {
            revert EthWithdrawalFailed();
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Margin Distribution
    ///////////////////////////////////////////////////////////////*/

    /// @notice accept a deposit amount and open new
    /// futures market position(s) all in a single tx
    /// @param _amount: amount of marginAsset to deposit into marginBase account
    /// @param _newPositions: an array of NewPosition's used to modify active market positions
    function depositAndDistribute(
        uint256 _amount,
        NewPosition[] memory _newPositions
    ) external onlyOwner {
        deposit(_amount);
        _distributeMargin(_newPositions);
    }

    /// @notice distribute margin across all/some positions specified via _newPositions
    /// @dev _newPositions may contain any number of new or existing positions
    /// @dev close and withdraw all margin from position if resulting position size is zero post trade
    /// @param _newPositions: an array of NewPosition's used to modify active market positions
    function distributeMargin(NewPosition[] memory _newPositions)
        external
        onlyOwner
    {
        _distributeMargin(_newPositions);
    }

    function _distributeMargin(NewPosition[] memory _newPositions) internal {
        /// @notice limit size of new position specs passed into distribute margin
        if (_newPositions.length > type(uint8).max) {
            revert MaxNewPositionsExceeded(_newPositions.length);
        }

        /// @notice tracking variable for calculating fee(s)
        uint256 totalSizeDeltaInUSD = 0;

        // for each new position in _newPositions, distribute margin accordingly
        for (uint8 i = 0; i < _newPositions.length; i++) {
            // define market params to be used to create or modify a position
            bytes32 marketKey = _newPositions[i].marketKey;
            int256 sizeDelta = _newPositions[i].sizeDelta;
            int256 marginDelta = _newPositions[i].marginDelta;

            // define market
            IFuturesMarket market = futuresMarket(marketKey);

            // fetch position size from Synthetix
            (, , , , int128 size) = market.positions(address(this));

            /// @dev check if position exists internally
            if (markets.get(uint256(marketKey))) {
                // check if position was liquidated
                if (size == 0) {
                    removeMarketKey(marketKey);
                    
                    // this position no longer exists internally
                    // thus, treat as new position
                    if (sizeDelta == 0) {
                        // position does not exist internally thus sizeDelta must be non-zero
                        revert ValueCannotBeZero("sizeDelta");
                    }
                }
                
                // check if position will be closed by newPosition's sizeDelta
                else if (size + sizeDelta == 0) {
                    removeMarketKey(marketKey);

                    // close position and withdraw margin
                    market.closePositionWithTracking(TRACKING_CODE);
                    market.withdrawAllMargin();

                    // continue to next newPosition
                    continue;
                }
            } else if (sizeDelta == 0) {
                // position does not exist internally thus sizeDelta must be non-zero
                revert ValueCannotBeZero("sizeDelta");
            }

            /// @notice execute trade
            /// @dev following trades will not result in position being closed
            /// @dev following trades may either modify or create a position
            if (marginDelta < 0) {
                // remove margin from market and potentially adjust position size
                totalSizeDeltaInUSD += modifyPositionForMarketAndWithdraw(
                    marginDelta,
                    sizeDelta,
                    market
                );

                // update internal accounting
                addMarketKey(marketKey);
            } else if (marginDelta > 0) {
                // deposit margin into market and potentially adjust position size
                totalSizeDeltaInUSD += depositAndModifyPositionForMarket(
                    marginDelta,
                    sizeDelta,
                    market
                );

                // update internal accounting
                addMarketKey(marketKey);
            } else if (sizeDelta != 0) {
                /// @notice adjust position size
                /// @notice no margin deposited nor withdrawn from market
                totalSizeDeltaInUSD += modifyPositionForMarket(
                    sizeDelta,
                    market
                );

                // update internal accounting
                addMarketKey(marketKey);
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

    /*///////////////////////////////////////////////////////////////
                        Execute Trades
    ///////////////////////////////////////////////////////////////*/

    /// @notice modify market position's size
    /// @dev _sizeDelta will always be non-zero
    /// @param _sizeDelta: size and position type (long/short) denominated in market synth
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function modifyPositionForMarket(int256 _sizeDelta, IFuturesMarket _market)
        internal
        returns (uint256 sizeDeltaInUSD)
    {
        /// @notice _sizeDelta is measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        sizeDeltaInUSD = (sUSDRate(_market) * _abs(_sizeDelta)) / 1e18;

        // modify position in specific market with KWENTA tracking code
        _market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
    }

    /// @notice deposit margin into specific market and potentially modify position size
    /// @dev _depositSize will always be greater than zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long/short) denominated in market synth
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
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
    }

    /// @notice potentially modify position size and withdraw margin from market
    /// @dev _withdrawalSize will always be less than zero
    /// @dev _sizeDelta may be zero (i.e. market position goes unchanged)
    /// @param _withdrawalSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denominated in market synth
    /// @param _market: synthetix futures market
    /// @return sizeDeltaInUSD _sizeDelta *in sUSD*
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawalSize,
        int256 _sizeDelta,
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
    }

    /*///////////////////////////////////////////////////////////////
                        Internal Accounting
    ///////////////////////////////////////////////////////////////*/

    /// @notice add marketKey to activeMarketKeys
    /// @param _marketKey to add
    function addMarketKey(bytes32 _marketKey) internal {
        if (!markets.get(uint256(_marketKey))) {
            // add to mapping
            marketKeyIndex[_marketKey] = activeMarketKeys.length;

            // add to end of array
            activeMarketKeys.push(_marketKey);

            // add to bitmap
            markets.setTo(uint256(_marketKey), true);
        }
    }

    /// @notice remove index from activeMarketKeys
    /// @param _marketKey to add
    function removeMarketKey(bytes32 _marketKey) internal {
        uint256 index = marketKeyIndex[_marketKey];
        assert(index < activeMarketKeys.length);

        // remove from mapping
        delete marketKeyIndex[_marketKey];

        // remove from array
        for (; index < activeMarketKeys.length - 1; ) {
            unchecked {
                // shift element in array to the left
                activeMarketKeys[index] = activeMarketKeys[index + 1];
                // update index for given market key
                marketKeyIndex[activeMarketKeys[index]] = index;
                index++;
            }
        }
        activeMarketKeys.pop();

        // remove from bitmap
        markets.setTo(uint256(_marketKey), false);
    }

    /*///////////////////////////////////////////////////////////////
                            Limit Orders
    ///////////////////////////////////////////////////////////////*/

    /// @notice limit order logic condition checker
    /// @param _orderId: key for an active order
    function validOrder(uint256 _orderId) public view returns (bool) {
        Order memory order = orders[_orderId];

        uint256 price = sUSDRate(futuresMarket(order.marketKey));

        if (order.sizeDelta > 0) {
            // Long
            return price <= order.desiredPrice;
        } else if (order.sizeDelta < 0) {
            // Short
            return price >= order.desiredPrice;
        }

        // sizeDelta == 0
        return false;
    }

    /// @notice register a limit order internally and with gelato
    /// @param _marketKey: synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of futures position
    /// @param _limitPrice: expected limit order price
    /// @return orderId contract interface
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _limitPrice
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
        MarginBase.NewPosition[]
            memory newPositions = new MarginBase.NewPosition[](1);
        newPositions[0] = NewPosition({
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
