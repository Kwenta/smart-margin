// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IMarginBaseTypes.sol";

/// @title Kwenta MarginBase Interface
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
interface IMarginBase is IMarginBaseTypes {
    /*///////////////////////////////////////////////////////////////
                                Views
    ///////////////////////////////////////////////////////////////*/

    function freeMargin() external view returns (uint256);

    function getPosition(bytes32 _marketKey)
        external
        returns (
            uint64 id,
            uint64 fundingIndex,
            uint128 margin,
            uint128 lastPrice,
            int128 size
        );

    /*///////////////////////////////////////////////////////////////
                                Mutative
    ///////////////////////////////////////////////////////////////*/

    // Account Deposit & Withdraw
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function withdrawEth(uint256 _amount) external;

    // Margin Distribution
    function distributeMargin(NewPosition[] memory _newPositions) external;

    function depositAndDistribute(
        uint256 _amount,
        NewPosition[] memory _newPositions
    ) external;

    // Limit Orders
    function validOrder(uint256 _orderId) external view returns (bool, uint256);

    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType
    ) external payable returns (uint256);

    function placeOrderWithFeeCap(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint256 _maxDynamicFee
    ) external payable returns (uint256);

    function cancelOrder(uint256 _orderId) external;

    function checker(uint256 _orderId)
        external
        view
        returns (bool canExec, bytes memory execPayload);
}
