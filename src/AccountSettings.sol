// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccountSettings} from "./interfaces/IAccountSettings.sol";

/// @title Kwenta Settings for Accounts
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Contract (owned by the deployer) for controlling the settings of account(s)
/// @dev This contract will require deployment prior to account creation
contract AccountSettings is IAccountSettings, Ownable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice max BPS; used for decimals calculations
    uint256 private constant MAX_BPS = 10000;

    /*//////////////////////////////////////////////////////////////
                                SETTINGS
    //////////////////////////////////////////////////////////////*/

    // @notice Kwenta's Treasury Address
    address public treasury;

    /// @dev fee imposed on all trades
    /// @dev trades: defined as changes made to IMarginBaseTypes.ActiveMarketPosition.size
    uint256 public tradeFee;

    /// @dev fee imposed on limit orders
    uint256 public limitOrderFee;

    /// @dev fee imposed on stop losses
    uint256 public stopOrderFee;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice set initial account fees
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
        if (_treasury == address(0)) revert ZeroAddress();

        /// @notice set Kwenta Treasury address
        treasury = _treasury;

        /// @notice ensure valid fees
        if (_tradeFee > MAX_BPS) revert InvalidFee(_tradeFee);
        if (_limitOrderFee > MAX_BPS) revert InvalidFee(_limitOrderFee);
        if (_stopOrderFee > MAX_BPS) revert InvalidFee(_stopOrderFee);

        /// @notice set initial fees
        tradeFee = _tradeFee;
        limitOrderFee = _limitOrderFee;
        stopOrderFee = _stopOrderFee;
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccountSettings
    function setTreasury(address _treasury) external override onlyOwner {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) revert ZeroAddress();

        // @notice ensure address will change
        if (_treasury == treasury) revert DuplicateAddress();

        /// @notice set Kwenta Treasury address
        treasury = _treasury;

        emit TreasuryAddressChanged(_treasury);
    }

    /// @inheritdoc IAccountSettings
    function setTradeFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == tradeFee) revert DuplicateFee();

        /// @notice set fee
        tradeFee = _fee;

        emit TradeFeeChanged(_fee);
    }

    /// @inheritdoc IAccountSettings
    function setLimitOrderFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == limitOrderFee) revert DuplicateFee();

        /// @notice set fee
        limitOrderFee = _fee;

        emit LimitOrderFeeChanged(_fee);
    }

    /// @inheritdoc IAccountSettings
    function setStopOrderFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == stopOrderFee) revert DuplicateFee();

        /// @notice set fee
        stopOrderFee = _fee;

        emit StopOrderFeeChanged(_fee);
    }
}
