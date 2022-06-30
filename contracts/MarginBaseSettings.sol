// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Kwenta Settings for MarginBase Accounts
/// @author JaredBorders
/// @notice Contract (owned by the deployer) for controlling the settings of MarginBase account(s)
/// @dev This contract will require deployment prior to MarginBase account creation
contract MarginBaseSettings is Ownable {
    /*///////////////////////////////////////////////////////////////
                                Constants
    ///////////////////////////////////////////////////////////////*/

    /// @notice decimals calculations
    uint256 private constant MAX_BPS = 10_000;

    /*///////////////////////////////////////////////////////////////
                        Settings
    ///////////////////////////////////////////////////////////////*/

    /// @notice denoted in Basis points (BPS) (One basis point is equal to 1/100th of 1%)
    uint256 public distributionFee;

    // @notice Kwenta's Treasury Address
    address public treasury;

    /*///////////////////////////////////////////////////////////////
                                Events
    ///////////////////////////////////////////////////////////////*/

    /// @notice emitted after a successful distribution fee change
    /// @param _distributionFee: fee denoted in BPS
    event DistributionFeeChanged(uint256 _distributionFee);

    /// @notice emitted after changing treasury address
    /// @param _treasury: new treasury address
    event TreasuryAddressChanged(address _treasury);

    /*///////////////////////////////////////////////////////////////
                        Constructor
    ///////////////////////////////////////////////////////////////*/

    /// @notice set initial fee imposed on calls to MarginBase.distributeMargin()
    /// @param _distributionFee: fee denoted in BPS
    constructor(uint256 _distributionFee, address _treasury) {
        require(_distributionFee < MAX_BPS, "Invalid Fee");
        distributionFee = _distributionFee;
        require(_treasury != address(0), "Invalid Address");
        treasury = _treasury;
    }

    /*///////////////////////////////////////////////////////////////
                        Getters/Setters
    ///////////////////////////////////////////////////////////////*/

    /// @notice set new distribution fee
    /// @param _distributionFee: fee denoted in BPS
    function setDistributionFee(uint256 _distributionFee) external onlyOwner {
        require(_distributionFee < MAX_BPS, "Invalid Fee");
        distributionFee = _distributionFee;
        emit DistributionFeeChanged(_distributionFee);
    }

    /// @notice set new treasury address
    /// @param _treasury: new treasury address
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid Address");
        treasury = _treasury;
        emit TreasuryAddressChanged(_treasury);
    }
}
