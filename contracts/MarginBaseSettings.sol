// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Kwenta Settings for MarginBase Accounts
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Contract (owned by the deployer) for controlling the settings of MarginBase account(s)
/// @dev This contract will require deployment prior to MarginBase account creation
contract MarginBaseSettings is Ownable {
    /*///////////////////////////////////////////////////////////////
                                Constants
    ///////////////////////////////////////////////////////////////*/

    /// @notice decimals calculations
    uint256 private constant MAX_BPS = 10000;

    /*///////////////////////////////////////////////////////////////
                        Settings
    ///////////////////////////////////////////////////////////////*/

    // @notice Kwenta's Treasury Address
    address public treasury;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on calls to distributeMargin()
    uint256 public distributionFee;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on all trades 
    /// @dev trades: defined as changes made to IMarginBaseTypes.ActiveMarketPosition.size
    uint256 public tradeFee;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on limit orders
    uint256 public limitOrderFee;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on stop losses
    uint256 public stopLossFee;

    /*///////////////////////////////////////////////////////////////
                                Events
    ///////////////////////////////////////////////////////////////*/

    /// @notice emitted after changing treasury address
    /// @param treasury: new treasury address
    event TreasuryAddressChanged(address treasury);

    /// @notice emitted after a successful distribution fee change
    /// @param fee: fee denoted in BPS
    event DistributionFeeChanged(uint256 fee);

    /// @notice emitted after a successful trade fee change
    /// @param fee: fee denoted in BPS
    event TradeFeeChanged(uint256 fee);

    /// @notice emitted after a successful limit order fee change
    /// @param fee: fee denoted in BPS
    event LimitOrderFeeChanged(uint256 fee);

    /// @notice emitted after a successful stop loss fee change
    /// @param fee: fee denoted in BPS
    event StopLossFeeChanged(uint256 fee);

    /*///////////////////////////////////////////////////////////////
                                Errors
    ///////////////////////////////////////////////////////////////*/

    /// @notice zero address cannot be used
    error ZeroAddress();

    /// @notice invalid fee (fee >= MAX_BPS)
    /// @param fee: fee denoted in BPS
    error InvalidFee(uint256 fee);

    /*///////////////////////////////////////////////////////////////
                            Constructor
    ///////////////////////////////////////////////////////////////*/

    /// @notice set initial fee imposed on calls to MarginBase.distributeMargin()
    /// @param _treasury: Kwenta's Treasury Address
    /// @param _distributionFee: fee denoted in BPS
    /// @param _tradeFee: fee denoted in BPS
    /// @param _limitOrderFee: fee denoted in BPS
    /// @param _stopLossFee: fee denoted in BPS
    constructor(
        address _treasury,
        uint256 _distributionFee,
        uint256 _tradeFee,
        uint256 _limitOrderFee,
        uint256 _stopLossFee
    ) {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) { revert ZeroAddress(); }
        
        /// @notice set Kwenta Treasury address 
        treasury = _treasury;

        /// @notice ensure valid fees
        if (_distributionFee >= MAX_BPS) { revert InvalidFee(_distributionFee); }
        if (_tradeFee >= MAX_BPS) { revert InvalidFee(_tradeFee); }
        if (_limitOrderFee >= MAX_BPS) { revert InvalidFee(_limitOrderFee); }
        if (_stopLossFee >= MAX_BPS) { revert InvalidFee(_stopLossFee); }

        /// @notice set initial fees
        distributionFee = _distributionFee;
        tradeFee = _tradeFee;
        limitOrderFee = _limitOrderFee;
        stopLossFee = _stopLossFee;
    }

    /*///////////////////////////////////////////////////////////////
                                Setters
    ///////////////////////////////////////////////////////////////*/

    /// @notice set new treasury address
    /// @param _treasury: new treasury address
    function setTreasury(address _treasury) external onlyOwner {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) { revert ZeroAddress(); }

        /// @notice set Kwenta Treasury address
        treasury = _treasury;

        emit TreasuryAddressChanged(_treasury);
    }

    /// @notice set new distribution fee
    /// @param _fee: fee denoted in BPS
    function setDistributionFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        /// @notice set fee
        distributionFee = _fee;

        emit DistributionFeeChanged(_fee);
    }

    /// @notice set new trade fee
    /// @param _fee: fee denoted in BPS
    function setTradeFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        /// @notice set fee
        tradeFee = _fee;

        emit TradeFeeChanged(_fee);
    }

    /// @notice set new limit order fee
    /// @param _fee: fee denoted in BPS
    function setLimitOrderFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        /// @notice set fee
        limitOrderFee = _fee;

        emit LimitOrderFeeChanged(_fee);
    }

    /// @notice set new stop loss fee
    /// @param _fee: fee denoted in BPS
    function setStopLossFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        /// @notice set fee
        stopLossFee = _fee;

        emit StopLossFeeChanged(_fee);
    }
}
