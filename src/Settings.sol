// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {ISettings} from "./interfaces/ISettings.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/// @title Kwenta Settings for Accounts
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
contract Settings is ISettings, Owned {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    uint256 public constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    address public treasury;

    /// @inheritdoc ISettings
    uint256 public tradeFee;

    /// @inheritdoc ISettings
    uint256 public limitOrderFee;

    /// @inheritdoc ISettings
    uint256 public stopOrderFee;

    /// @inheritdoc ISettings
    uint256 public delegateFeeProportion;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice set initial account fees
    /// @param _owner: owner of the contract
    /// @param _treasury: Kwenta's Treasury Address
    /// @param _tradeFee: fee denoted in BPS
    /// @param _limitOrderFee: fee denoted in BPS
    /// @param _stopOrderFee: fee denoted in BPS
    constructor(
        address _owner,
        address _treasury,
        uint256 _tradeFee,
        uint256 _limitOrderFee,
        uint256 _stopOrderFee
    ) Owned(_owner) {
        treasury = _treasury;

        /// @notice ensure valid fees
        if (_tradeFee > MAX_BPS) revert InvalidFee(_tradeFee);
        if (_limitOrderFee > MAX_BPS) revert InvalidFee(_limitOrderFee);
        if (_stopOrderFee > MAX_BPS) revert InvalidFee(_stopOrderFee);

        /// @notice set initial fees
        tradeFee = _tradeFee;
        limitOrderFee = _limitOrderFee;
        stopOrderFee = _stopOrderFee;

        /// @dev delegateFeeProportion is left as default value of 0
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISettings
    function setTreasury(address _treasury) external override onlyOwner {
        /// @notice ensure valid address for Kwenta Treasury
        if (_treasury == address(0)) revert ZeroAddress();

        // @notice ensure address will change
        if (_treasury == treasury) revert DuplicateAddress();

        /// @notice set Kwenta Treasury address
        treasury = _treasury;

        emit TreasuryAddressChanged(_treasury);
    }

    /// @inheritdoc ISettings
    function setTradeFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == tradeFee) revert DuplicateFee();

        /// @notice set fee
        tradeFee = _fee;

        emit TradeFeeChanged(_fee);
    }

    /// @inheritdoc ISettings
    function setLimitOrderFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == limitOrderFee) revert DuplicateFee();

        /// @notice set fee
        limitOrderFee = _fee;

        emit LimitOrderFeeChanged(_fee);
    }

    /// @inheritdoc ISettings
    function setStopOrderFee(uint256 _fee) external override onlyOwner {
        /// @notice ensure valid fee
        if (_fee > MAX_BPS) revert InvalidFee(_fee);

        // @notice ensure fee will change
        if (_fee == stopOrderFee) revert DuplicateFee();

        /// @notice set fee
        stopOrderFee = _fee;

        emit StopOrderFeeChanged(_fee);
    }

    /// @inheritdoc ISettings
    function setDelegateFeeProportion(uint256 _feeProportion)
        external
        override
        onlyOwner
    {
        /// @notice ensure valid fee proportion
        if (_feeProportion > MAX_BPS) revert InvalidFee(_feeProportion);

        // @notice ensure fee proportion will change
        if (_feeProportion == delegateFeeProportion) revert DuplicateFee();

        /// @notice set fee proportion
        delegateFeeProportion = _feeProportion;

        emit DelegateFeeProportionChanged(_feeProportion);
    }
}
