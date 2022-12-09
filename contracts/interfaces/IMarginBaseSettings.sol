// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title Kwenta MarginBaseSettings Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginBaseSettings {
    function limitOrderFee() external view returns (uint256);

    function setLimitOrderFee(uint256 _fee) external;

    function setStopOrderFee(uint256 _fee) external;

    function setTradeFee(uint256 _fee) external;

    function setTreasury(address _treasury) external;

    function stopOrderFee() external view returns (uint256);

    function tradeFee() external view returns (uint256);

    function treasury() external view returns (address);
}
