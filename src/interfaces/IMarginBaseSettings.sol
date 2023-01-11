// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title Kwenta MarginBaseSettings Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginBaseSettings {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after changing treasury address
    /// @param treasury: new treasury address
    event TreasuryAddressChanged(address treasury);

    /// @notice emitted after a successful trade fee change
    /// @param fee: fee denoted in BPS
    event TradeFeeChanged(uint256 fee);

    /// @notice emitted after a successful limit order fee change
    /// @param fee: fee denoted in BPS
    event LimitOrderFeeChanged(uint256 fee);

    /// @notice emitted after a successful stop loss fee change
    /// @param fee: fee denoted in BPS
    event StopOrderFeeChanged(uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice zero address cannot be used
    error ZeroAddress();

    /// @notice invalid fee (fee > MAX_BPS)
    /// @param fee: fee denoted in BPS
    error InvalidFee(uint256 fee);

    /// @notice new fee cannot be the same as the old fee
    error DuplicateFee();

    /// @notice new address cannot be the same as the old address
    error DuplicateAddress();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    // @notice Kwenta's Treasury Address
    function treasury() external view returns (address);

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on all trades
    /// @dev trades: defined as changes made to IMarginBaseTypes.ActiveMarketPosition.size
    function tradeFee() external view returns (uint256);

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on limit orders
    function limitOrderFee() external view returns (uint256);

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on stop losses
    function stopOrderFee() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice set new limit order fee
    /// @param _fee: fee denoted in BPS
    function setLimitOrderFee(uint256 _fee) external;

    /// @notice set new stop loss fee
    /// @param _fee: fee denoted in BPS
    function setStopOrderFee(uint256 _fee) external;

    /// @notice set new trade fee
    /// @param _fee: fee denoted in BPS
    function setTradeFee(uint256 _fee) external;

    /// @notice set new treasury address
    /// @param _treasury: new treasury address
    function setTreasury(address _treasury) external;
}
