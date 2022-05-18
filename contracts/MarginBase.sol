// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IFuturesMarket.sol";

contract MarginBase is MinimalProxyable {

    // tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    //////////////////////////////////////
    /////////////// STATE ////////////////
    //////////////////////////////////////

    // synthetix address resolver
    IAddressResolver private addressResolver;

    // token contract used for account margin
    IERC20 public marginAsset;

    // market keys mapped to active market positions
    mapping(bytes32 => MarketPosition) public activeMarketPositions;

    //////////////////////////////////////
    ////////// DATA-STRUCTURES ///////////
    //////////////////////////////////////

    struct MarketPosition {
        uint size;
        uint leverage;
        bytes32 marketKey;
    }

    //////////////////////////////////////
    ///////////// MODIFIERS //////////////
    //////////////////////////////////////
    
    modifier validLeverage(int8 _leverage) {
        require(_leverage <= 10, "Leverage must not exceed 10");
        require(_leverage > 0, "Leverage must exceed 0");
        _;
    }

    //////////////////////////////////////
    //// CONSTRUCTOR / INITIALIZER ///////
    //////////////////////////////////////

    /// @notice constructor never used except for first CREATE
    constructor() MinimalProxyable() {}

    function initialize(address _marginAsset, address _addressResolver) external initOnce {
        marginAsset = IERC20(_marginAsset);
        addressResolver = IAddressResolver(_addressResolver);

        /// @dev the Ownable constructor is never called when we create minimal proxies
        _transferOwnership(msg.sender);
    }
    
    //////////////////////////////////////
    ///////// EXTERNAL FUNCTIONS /////////
    //////////////////////////////////////

    /// @notice deposit amount of marginAsset into account
    function deposit(uint _amount) external onlyOwner {
        marginAsset.transferFrom(owner(), address(this), _amount);
    }

    /// @notice withdraw amount of marginAsset from account
    function withdraw(uint _amount) external onlyOwner {
        marginAsset.transfer(owner(), _amount);
    }

    function depositAndModifyPositionForMarket(
        int256 _size,
        bytes32 _marketKey,
        int8 _leverage
    ) external onlyOwner validLeverage(_leverage) {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(_size);

        // modify position in specific market with KWENTA tracking code
        // @TODO: how to define sizeDelta
        int256 sizeDelta = _size; // * _leverage ????
        market.modifyPositionWithTracking(sizeDelta, TRACKING_CODE);
    }

    function modifyPositionForMarketAndWithdraw(
        int256 _size,
        bytes32 _marketKey,
        int8 _leverage
    ) external onlyOwner {
        // define market via _marketKey
        IFuturesMarket market = futuresMarket(_marketKey);

        // modify position in specific market with KWENTA tracking code
        // @TODO: how to define sizeDelta
        int256 sizeDelta = _size; // * leverage ????
        market.modifyPositionWithTracking(sizeDelta, TRACKING_CODE);

        /// @notice alter the amount of margin in specific market position
        /// @dev positive input triggers a deposit; a negative one, a withdrawal
        market.transferMargin(_size * -1);
    }

    function rebalance() external {
        // @TODO: Rebalance margin in an equal manner
    }


    //////////////////////////////////////
    ///////// INTERNAL FUNCTIONS /////////
    //////////////////////////////////////

    /// @notice addressResolver fetches IFuturesMarket address for specific market
    function futuresMarket(bytes32 _marketKey) internal view returns (IFuturesMarket) {
        return IFuturesMarket(addressResolver.requireAndGetAddress(
            _marketKey, 
            "MarginBase: Could not get Futures Market"
        ));
    }

}
