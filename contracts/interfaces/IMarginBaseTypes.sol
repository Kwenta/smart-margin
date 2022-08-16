// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title Kwenta MarginBase Types
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Types used in Margin Base Accounts
interface IMarginBaseTypes {
    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    // denotes order types for code clarity
    /// @dev under the hood LIMIT = 0, STOP = 1
    enum OrderTypes {
        LIMIT,
        STOP
    }

    // marketKey: synthetix futures market id/key
    // margin: amount of margin (in sUSD) in specific futures market
    // size: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    struct ActiveMarketPosition {
        bytes32 marketKey;
        uint128 margin;
        int128 size;
    }

    // marketKey: synthetix futures market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    struct UpdateMarketPositionSpec {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
    }

    // marketKey: synthetix futures market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    // targetPrice: limit or stop price to fill at
    // gelatoTaskId: unqiue taskId from gelato necessary for cancelling orders
    // orderType: order type to determine order fill logic
    struct Order {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
        uint256 targetPrice;
        bytes32 gelatoTaskId;
        OrderTypes orderType;
    }
}
