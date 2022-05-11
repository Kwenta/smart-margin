// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";

contract MarginBase is MinimalProxyable {

    constructor() MinimalProxyable() {}

    /*function initialize(address baseAsset) external initOnce {
        initialize();
    }*/

    function deposit(uint amount) public onlyOwner {
        // @TODO: Deposit sUSD into margin account
    }

    function withdraw(uint amount) external onlyOwner {
        // @TODO: Withdraw sUSD from margin account
    }

    //////////////////////////////////////
    //////////// CROSS MARGIN ////////////
    //////////////////////////////////////

    function tradeForMarket(int size, bytes32 marketKey) external onlyOwner {
        // @TODO: Modify position for given market
    }

    function rebalance() external {
        // @TODO: Rebalance margin in an equal manner
    }

}
