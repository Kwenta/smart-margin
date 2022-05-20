// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";

// @TODO: Document
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

    /// @notice deposit amount of marginAsset into account
    function deposit(uint256 _amount) external onlyOwner {
        marginAsset.transferFrom(owner(), address(this), _amount);
    }

    /// @notice withdraw amount of marginAsset from account
    function withdraw(uint256 _amount) external onlyOwner {
        marginAsset.transfer(owner(), _amount);
    }

    // @TODO: Document
    function closeMarketPosition(bytes32 _marketKey) external onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // close market position with KWENTA tracking code
        market.closePositionWithTracking(TRACKING_CODE);

        /// @dev update state:
        // delete formerly active position
        removeActiveMarketPositon(_marketKey);
    }

    // @TODO: Document
    function depositAndModifyPositionForMarket(
        int256 _depositSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) external onlyOwner {
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

    // @TODO: Document
    function modifyPositionForMarketAndWithdraw(
        int256 withdrawSize,
        int256 _sizeDelta,
        bytes32 _marketKey
    ) external onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // modify position in specific market with KWENTA tracking code
        market.modifyPositionWithTracking(_sizeDelta, TRACKING_CODE);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(withdrawSize);

        // fetch new position data from Synthetix
        (, , uint128 margin, , int128 size) = market.positions(address(this));

        // update state for given open market position
        updateActiveMarketPosition(_marketKey, margin, size);
    }

    // @TODO: Document
    function rebalance(
        ActiveMarketPosition[] memory newPositions
    ) external {
        /*
        
        [newPosition0, newPosition2, newPosition3, ..., newPositionN]

            ------->
        FOR-EACH newPosition:

            find market and then,
                if newPositionN.newMargin less than oldMargin (i.e. reducing margin)
                    -> modifyPositionForMarketAndWithdraw(oldMargin - newPositionN.newMargin, newPositionN.newSize, marketKey)
                if newMargin greater than oldMargin (i.e. increasing margin)
                    -> depositAndModifyPositionForMarket(newPositionN.newMargin - oldMargin, newPositionN.newSize, marketKey)
                else no change

        */
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

    // @TODO: Document
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

    // @TODO: Document
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
