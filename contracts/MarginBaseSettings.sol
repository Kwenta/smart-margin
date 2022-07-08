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
    /// @param distributionFee: fee denoted in BPS
    event DistributionFeeChanged(uint256 distributionFee);

    /// @notice emitted after a successful limit order fee change
    /// @param limitOrderFee: fee denoted in BPS
    event LimitOrderFeeChanged(uint256 limitOrderFee);

    /// @notice emitted after a successful stop loss fee change
    /// @param stopLossFee: fee denoted in BPS
    event StopLossFeeChanged(uint256 stopLossFee);

    /*///////////////////////////////////////////////////////////////
                                Errors
    ///////////////////////////////////////////////////////////////*/

    /// @notice zero address cannot be used
    error ZeroAddress();

    /// @notice invalid distribution fee
    /// @param fee: fee denoted in BPS
    error InvalidDistributionFee(uint256 fee);

    /// @notice invalid limit order fee
    /// @param fee: fee denoted in BPS
    error InvalidLimitOrderFee(uint256 fee);

    /// @notice invalid stop loss fee
    /// @param fee: fee denoted in BPS
    error InvalidStopLossFee(uint256 fee);

    /*///////////////////////////////////////////////////////////////
                            Constructor
    ///////////////////////////////////////////////////////////////*/

    /// @notice set initial fee imposed on calls to MarginBase.distributeMargin()
    /// @param _treasury: Kwenta's Treasury Address
    /// @param _distributionFee: fee denoted in BPS
    /// @param _limitOrderFee: fee denoted in BPS
    /// @param _stopLossFee: fee denoted in BPS
    constructor(
        address _treasury,
        uint256 _distributionFee,
        uint256 _limitOrderFee,
        uint256 _stopLossFee
    ) {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) { revert ZeroAddress(); }
        
        /// @notice set Kwenta Treasury address 
        treasury = _treasury;

        /// @notice ensure valid fees
        if (_distributionFee >= MAX_BPS) { revert InvalidDistributionFee(_distributionFee); }
        if (_limitOrderFee >= MAX_BPS) { revert InvalidLimitOrderFee(_limitOrderFee); }
        if (_stopLossFee >= MAX_BPS) { revert InvalidStopLossFee(_stopLossFee); }

        /// @notice set initial fees
        distributionFee = _distributionFee;
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
    /// @param _distributionFee: fee denoted in BPS
    function setDistributionFee(uint256 _distributionFee) external onlyOwner {
        /// @notice ensure valid fee
        if (_distributionFee >= MAX_BPS) { revert InvalidDistributionFee(_distributionFee); }

        /// @notice set fee
        distributionFee = _distributionFee;

        emit DistributionFeeChanged(distributionFee);
    }

    /// @notice set new limit order fee
    /// @param _limitOrderFee: fee denoted in BPS
    function setLimitOrderFee(uint256 _limitOrderFee) external onlyOwner {
        /// @notice ensure valid fee
        if (_limitOrderFee >= MAX_BPS) { revert InvalidLimitOrderFee(_limitOrderFee); }

        /// @notice set fee
        limitOrderFee = _limitOrderFee;

        emit LimitOrderFeeChanged(limitOrderFee);
    }

    /// @notice set new stop loss fee
    /// @param _stopLossFee: fee denoted in BPS
    function setStopLossFee(uint256 _stopLossFee) external onlyOwner {
        /// @notice ensure valid fee
        if (_stopLossFee >= MAX_BPS) { revert InvalidStopLossFee(_stopLossFee); }

        /// @notice set fee
        stopLossFee = _stopLossFee;

        emit StopLossFeeChanged(stopLossFee);
    }
}
