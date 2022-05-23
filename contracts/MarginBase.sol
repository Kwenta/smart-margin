// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";

/// @title MarginBase
/// @notice MarginBase provides users a way to open multiple positions from the same base account
/// with cross-margin. Margin can be customly balanced across different positions. 
contract MarginBase is MinimalProxyable {
    //////////////////////////////////////
    ///////////// CONSTANTS //////////////
    //////////////////////////////////////

    // tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    //////////////////////////////////////
    /////////////// TYPES ////////////////
    //////////////////////////////////////

    struct ActiveMarketPosition {
        bytes32 marketKey;
        uint128 margin;
        int128 size;
    }

    struct UpdateMarketPositionSpec {
        bytes32 marketKey;
        int256 marginDelta;
        int256 sizeDelta;
    }

    //////////////////////////////////////
    /////////////// STATE ////////////////
    //////////////////////////////////////

    // synthetix address resolver
    IAddressResolver private addressResolver;

    // token contract used for account margin
    IERC20 public marginAsset;

    // number of active market positions account has
    uint16 public numberOfActivePositions = 0;

    // market keys that the account has active positions in
    bytes32[] public activeMarketKeys;

    // market keys mapped to active market positions
    mapping(bytes32 => ActiveMarketPosition) public activeMarketPositions;

    //////////////////////////////////////
    ///////////// MODIFIERS //////////////
    //////////////////////////////////////

    // @TODO: TBD

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

    /// @notice rebalance margin in all positions specificed via _newPositions
    /// @dev `_newPositions` does not necessarily contain ALL positions nor does the new allocation 
    /// have to be equally distributed. Distribution is up to the caller
    /// @dev it is up to the caller to ensure UpdateMarketPositionSpec is valid. Otherwise
    /// call with be reverted via Synthetix's FuturesMarket
    /// @param _newPositions: an array of UpdateMarketPositionSpec's used to modify active market positions
    function rebalance(
        UpdateMarketPositionSpec[] memory _newPositions
    ) external {

        // for each new position in _newPositions, rebalance accordingly and update state
        for (uint256 i = 0; i < _newPositions.length; i++) {
            // establish market
            bytes32 marketKey = _newPositions[i].marketKey;

            // establish old position to compare to new
            ActiveMarketPosition memory oldPosition = activeMarketPositions[marketKey];
            require(oldPosition.marketKey != 0, "MarginBase: Invalid _newPositions");

            int256 marginDelta = _newPositions[i].marginDelta;
            int256 sizeDelta = _newPositions[i].sizeDelta;
            
            /// @notice remove margin from market and potentially adjust size
            if (marginDelta < 0) {
                modifyPositionForMarketAndWithdraw(
                    marginDelta,
                    sizeDelta,
                    marketKey
                );

            /// @notice deposit margin into market and potentially adjust size
            /// @dev marginDelta >= 0
            } else {
                // if marginDelta is 0, there will simply be NO additional 
                // margin deposited into the market
                depositAndModifyPositionForMarket(
                    marginDelta,
                    sizeDelta,
                    marketKey
                );
            }
        }
    }

    //////////////////////////////////////
    ////////// PUBLIC FUNCTIONS //////////
    //////////////////////////////////////

    /// @notice close market position (note: not just modify position to 0 margin)
    /// @param _marketKey: synthetix futures market id/key
    function closeMarketPosition(bytes32 _marketKey) public onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // close market position with KWENTA tracking code
        market.closePositionWithTracking(TRACKING_CODE);
        
        /// @dev update state
        removeActiveMarketPositon(_marketKey);
    }

    /// @notice deposit margin into specific market, either creating or adding
    /// to a position and then updating account's active positions for user
    /// @param _depositSize: size of deposit in sUSD
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) public onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(_depositSize);

        // modify position in specific market with KWENTA tracking code
        market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size);
    }

    /// @notice modify active position and withdraw marginAsset from market into this account
    /// @param _withdrawSize: size of sUSD to withdraw from market into account
    /// @param _sizeDelta: size and position type (long//short) denoted in market synth (ex: sETH)
    /// @param _marketKey: synthetix futures market id/key
    function modifyPositionForMarketAndWithdraw(
        int256 _withdrawSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) public onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // modify position in specific market with KWENTA tracking code
        market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(_withdrawSize);

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size);
    }

    //////////////////////////////////////
    ///////// INTERNAL FUNCTIONS /////////
    //////////////////////////////////////

    /// @notice addressResolver fetches IFuturesMarket address for specific market
    function futuresMarket(
        bytes32 _marketKey
    ) internal view returns (IFuturesMarket) {
        return IFuturesMarket(addressResolver.requireAndGetAddress(
                _marketKey,
                "MarginBase: Could not get Futures Market"
            )
        );
    }

    /// @notice used internally to update contract state for the account's active position tracking
    function updateActiveMarketPosition(
        bytes32 _marketKey,
        uint128 _margin,
        int128 _size
    ) internal {
        ActiveMarketPosition memory newPosition = ActiveMarketPosition(
            _marketKey,
            _margin,
            _size
        );

        // check if this is updating a position or creating one
        if (activeMarketPositions[_marketKey].marketKey == 0) {
            activeMarketKeys.push(_marketKey);
            numberOfActivePositions++;
        }

        // update state of active market positions
        activeMarketPositions[_marketKey] = newPosition;
    }

    /// @notice used internally to update (remove) contract state for the account's active position tracking
    function removeActiveMarketPositon(bytes32 _marketKey) internal {
        delete activeMarketPositions[_marketKey];
        numberOfActivePositions--;

        require(activeMarketKeys.length > 0, "MarginBase: Empty array");
        bool found = false;

        for (uint256 i = 0; i < activeMarketKeys.length; i++) {
            // once `_marketKey` is encountered, swap with
            // last element in array exit for-loop
            if (activeMarketKeys[i] == _marketKey) {
                activeMarketKeys[i] = activeMarketKeys[
                    activeMarketKeys.length - 1
                ];
                found = true;
                break;
            }
        }
        // remove last element (which will be `_marketKey`)
        require(found, "MarginBase: Market Key not found");
        activeMarketKeys.pop();
    }
}
