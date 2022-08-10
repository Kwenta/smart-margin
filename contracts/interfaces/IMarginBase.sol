// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./IMarginBaseTypes.sol";

/// @title Kwenta MarginBase Interface
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IMarginBase is IMarginBaseTypes {
    /*///////////////////////////////////////////////////////////////
                                Views
    ///////////////////////////////////////////////////////////////*/

    function getNumberOfActivePositions() external view returns (uint256);
    function getAllActiveMarketPositions() external view returns (ActiveMarketPosition[] memory);
    function freeMargin() external view returns (uint256);

    /*///////////////////////////////////////////////////////////////
                                Mutative
    ///////////////////////////////////////////////////////////////*/

    // Account Deposit & Withdraw
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function withdrawEth(uint256 _amount) external;

    // Margin Distribution
    function distributeMargin(UpdateMarketPositionSpec[] memory _newPositions) external;
    function depositAndDistribute(uint256 _amount, UpdateMarketPositionSpec[] memory _newPositions) external;

    // Limit Orders
    function validOrder(uint256 _orderId) external view returns (bool);
    function placeOrder(bytes32 _marketKey, int256 _marginDelta, int256 _sizeDelta, uint256 _limitPrice) external payable returns (uint256);
    function cancelOrder(uint256 _orderId) external;
    function checker(uint256 _orderId) external view returns (bool canExec, bytes memory execPayload);
}
