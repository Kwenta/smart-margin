// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title Kwenta MarginBase Types
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Types used in Margin Base Accounts
interface IMarginBaseTypes {
    /*///////////////////////////////////////////////////////////////
                                Types
    ///////////////////////////////////////////////////////////////*/

    /// @notice Command Flags used to decode commands to execute
    enum Command {
        PERPS_V2_MODIFY_MARGIN,
        PERPS_V2_EXIT,
        PERPS_V2_SUBMIT_ATOMIC_ORDER,
        PERPS_V2_SUBMIT_DELAYED_ORDER,
        PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER,
        PERPS_V2_CANCEL_DELAYED_ORDER,
        PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
    }
    
    // denotes order types for code clarity
    /// @dev under the hood LIMIT = 0, STOP = 1
    enum OrderTypes {
        LIMIT,
        STOP
    }

    // marketKey: Synthetix PerpsV2 Market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    struct NewPosition {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta; // difference in position
        uint128 priceImpactDelta; // price impact tolerance as a percentage used on fillPrice at execution
    }

    // marketKey: Synthetix PerpsV2 Market id/key
    // marginDelta: amount of margin (in sUSD) to deposit or withdraw
    // sizeDelta: denoted in market currency (i.e. ETH, BTC, etc), size of futures position
    // targetPrice: limit or stop price to fill at
    // gelatoTaskId: unqiue taskId from gelato necessary for cancelling orders
    // orderType: order type to determine order fill logic
    // maxDynamicFee: dynamic fee cap in 18 decimal form; 0 for no cap
    struct Order {
        bytes32 marketKey;
        int256 marginDelta; // positive indicates deposit, negative withdraw
        int256 sizeDelta;
        uint256 targetPrice;
        bytes32 gelatoTaskId;
        OrderTypes orderType;
        uint256 maxDynamicFee;
        uint128 priceImpactDelta; // price impact tolerance as a percentage used on fillPrice at execution
    }
}
