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
    /// @dev fee imposed on all trades 
    /// @dev trades: defined as changes made to IMarginBaseTypes.ActiveMarketPosition.size
    uint256 public tradeFee;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on limit orders
    uint256 public limitOrderFee;

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    /// @dev fee imposed on stop losses
    uint256 public stopOrderFee;

    /*///////////////////////////////////////////////////////////////
                                Events
    ///////////////////////////////////////////////////////////////*/

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

    /*///////////////////////////////////////////////////////////////
                                Errors
    ///////////////////////////////////////////////////////////////*/

    /// @notice zero address cannot be used
    error ZeroAddress();

    /// @notice invalid fee (fee >= MAX_BPS)
    /// @param fee: fee denoted in BPS
    error InvalidFee(uint256 fee);

    /// @notice new fee cannot be the same as the old fee
    error DuplicateFee();

    /*///////////////////////////////////////////////////////////////
                            Constructor
    ///////////////////////////////////////////////////////////////*/

    /// @notice set initial margin base account fees
    /// @param _treasury: Kwenta's Treasury Address
    /// @param _tradeFee: fee denoted in BPS
    /// @param _limitOrderFee: fee denoted in BPS
    /// @param _stopOrderFee: fee denoted in BPS
    constructor(
        address _treasury,
        uint256 _tradeFee,
        uint256 _limitOrderFee,
        uint256 _stopOrderFee
    ) {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) { revert ZeroAddress(); }
        
        /// @notice set Kwenta Treasury address 
        treasury = _treasury;

        /// @notice ensure valid fees
        if (_tradeFee >= MAX_BPS) { revert InvalidFee(_tradeFee); }
        if (_limitOrderFee >= MAX_BPS) { revert InvalidFee(_limitOrderFee); }
        if (_stopOrderFee >= MAX_BPS) { revert InvalidFee(_stopOrderFee); }

        /// @notice set initial fees
        tradeFee = _tradeFee;
        limitOrderFee = _limitOrderFee;
        stopOrderFee = _stopOrderFee;
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

    /// @notice set new trade fee
    /// @param _fee: fee denoted in BPS
    function setTradeFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        // @notice ensure fee will change
        if (_fee == tradeFee) revert DuplicateFee();

        /// @notice set fee
        tradeFee = _fee;

        emit TradeFeeChanged(_fee);
    }

    /// @notice set new limit order fee
    /// @param _fee: fee denoted in BPS
    function setLimitOrderFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        // @notice ensure fee will change
        if (_fee == limitOrderFee) revert DuplicateFee();

        /// @notice set fee
        limitOrderFee = _fee;

        emit LimitOrderFeeChanged(_fee);
    }

    /// @notice set new stop loss fee
    /// @param _fee: fee denoted in BPS
    function setStopOrderFee(uint256 _fee) external onlyOwner {
        /// @notice ensure valid fee
        if (_fee >= MAX_BPS) { revert InvalidFee(_fee); }

        // @notice ensure fee will change
        if (_fee == stopOrderFee) revert DuplicateFee();

        /// @notice set fee
        stopOrderFee = _fee;

        emit StopOrderFeeChanged(_fee);
    }
}
