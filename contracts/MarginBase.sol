// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";
import "./interfaces/IFuturesMarketManager.sol";

/// @title MarginBase
/// @notice MarginBase provides users a way to open multiple positions from the same base account
///                    with cross-margin. Margin can be customly balanced across different positions.
contract MarginBase is MinimalProxyable {
    //////////////////////////////////////
    ///////////// CONSTANTS //////////////
    //////////////////////////////////////

    // tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    // name for futures market manager, needed for fetching market key
    bytes32 private constant FUTURES_MANAGER = "FuturesMarketManager";

    //////////////////////////////////////
    /////////////// TYPES ////////////////
    //////////////////////////////////////

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

    //////////////////////////////////////
    /////////////// STATE ////////////////
    //////////////////////////////////////

    // synthetix address resolver
    IAddressResolver private addressResolver;

    // synthetix futures market manager
    IFuturesMarketManager private futuresManager;

    // token contract used for account margin
    IERC20 public marginAsset;

    // market keys that the account has active positions in
    bytes32[] public activeMarketKeys;

    // market keys mapped to active market positions
    mapping(bytes32 => ActiveMarketPosition) public activeMarketPositions;

    //////////////////////////////////////
    /////////////// ERRORS ///////////////
    //////////////////////////////////////

    /// deposit size was negative
    /// @param depositSize: amount of margin asset to deposit into market
    error InvalidDepositSize(int256 depositSize);

    /// withdraw size was positive
    /// @param withdrawSize: amount of margin asset to withdraw from market
    error InvalidWithdrawSize(int256 withdrawSize);

    //////////////////////////////////////
    //// CONSTRUCTOR / INITIALIZER ///////
    //////////////////////////////////////

    /// @notice constructor never used except for first CREATE
    constructor() MinimalProxyable() {}

    function initialize(address _marginAsset, address _addressResolver)
        external
        initOnce
    {
        marginAsset = IERC20(_marginAsset);
        addressResolver = IAddressResolver(_addressResolver);
        futuresManager = IFuturesMarketManager(
            addressResolver.requireAndGetAddress(
                FUTURES_MANAGER,
                "MarginBase: Could not get Futures Market Manager"
            )
        );

        /// @dev the Ownable constructor is never called when we create minimal proxies
        _transferOwnership(msg.sender);
    }

    //////////////////////////////////////
    ///////// EXTERNAL FUNCTIONS /////////
    //////////////////////////////////////

    /// @param _amount: amount of marginAsset to deposit into marginBase account
    function deposit(uint256 _amount) external onlyOwner {
        marginAsset.transferFrom(owner(), address(this), _amount);
    }

    /// @param _amount: amount of marginAsset to withdraw from marginBase account
    function withdraw(uint256 _amount) external onlyOwner {
        marginAsset.transfer(owner(), _amount);
    }

    // @TODO: Gas Optimization
    /// @notice distribute margin across all/some positions specified via _newPositions
    /// @dev _newPositions may contain any number of new or existing positions
    /// @dev caller can close and withdraw all margin from position if _newPositions[i].isClosing is true
    /// @param _newPositions: an array of UpdateMarketPositionSpec's used to modify active market positions
    function distributeMargin(UpdateMarketPositionSpec[] calldata _newPositions)
        external
        onlyOwner
    {
        // for each new position in _newPositions, distribute margin accordingly and update state
        for (uint256 i = 0; i < _newPositions.length; i++) {
            if (_newPositions[i].isClosing) {
                /// @notice close position and transfer margin back to account
                closePositionAndWithdraw(_newPositions[i].marketKey);
            } else if (_newPositions[i].marginDelta < 0) {
                /// @notice remove margin from market and potentially adjust size
                modifyPositionForMarketAndWithdraw(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey
                );
            } else {
                /// @dev marginDelta >= 0
                /// @notice deposit margin into market and potentially adjust size
                depositAndModifyPositionForMarket(
                    _newPositions[i].marginDelta,
                    _newPositions[i].sizeDelta,
                    _newPositions[i].marketKey
                );
                // if marginDelta is 0, there will simply be NO additional
                // margin deposited into the market
            }
        }
    }

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

    //////////////////////////////////////
    ///////// INTERNAL FUNCTIONS /////////
    //////////////////////////////////////

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

    /// @notice deposit margin into specific market, either creating or adding
    ///         to a position and then updating account's active positions for user
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) internal {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        if (_depositSize < 0) {
            revert InvalidDepositSize(_depositSize);
        }
        market.transferMargin(_depositSize);

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // modify position in specific market with KWENTA tracking code
            market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size, market);
    }

    /// @notice modify active position and withdraw marginAsset from market into this account
    /// @param _withdrawSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) internal {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @dev if _sizeDelta is 0, then we do not want to modify position size, only margin
        if (_sizeDelta != 0) {
            // modify position in specific market with KWENTA tracking code
            market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);
        }

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        if (_withdrawSize > 0) {
            revert InvalidWithdrawSize(_withdrawSize);
        }
        market.transferMargin(_withdrawSize);

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size, market);
    }

    /// @notice closes futures position and withdraws all margin in that market back to this account
    /// @param _marketKey: synthetix futures market id/key
    function closePositionAndWithdraw(bytes32 _marketKey) internal {
        // update state (remove market)
        removeActiveMarketPositon(_marketKey);

        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // close position
        market.closePosition();

        // withdraw margin back to this account
        market.withdrawAllMargin();
    }

    /// @notice used internally to update contract state for the account's active position tracking
    /// @param _marketKey: key for synthetix futures market
    /// @param _margin: amount of margin the specific market position has
    /// @param _size: represents size of position (i.e. accounts for leverage)
    /// @dev if _size becomes 0, remove position from account state and withdraw margin
    function updateActiveMarketPosition(
        bytes32 _marketKey,
        uint128 _margin,
        int128 _size,
        IFuturesMarket market
    ) internal {
        if (_size == 0) {
            // update state (remove market)
            removeActiveMarketPositon(_marketKey);

            // withdraw margin back to this account
            market.withdrawAllMargin();
            return;
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

    /// @notice used internally to update contract state for the account's
    ///         active position tracking (remove market position)
    /// @dev removeActiveMarketPositon can ONLY be reached when _marketKey
    ///      is valid (i.e. there was an active position in that market)
    /// @param _marketKey: key for previously active market position
    function removeActiveMarketPositon(bytes32 _marketKey) internal {
        delete activeMarketPositions[_marketKey];

        for (uint16 i = 0; i < activeMarketKeys.length; i++) {
            // once _marketKey is encountered, swap with
            // last element in array and exit for-loop
            if (activeMarketKeys[i] == _marketKey) {
                activeMarketKeys[i] = activeMarketKeys[
                    activeMarketKeys.length - 1
                ];
                break;
            }
        }
        // remove last element (which will be _marketKey)
        activeMarketKeys.pop();
    }
}
