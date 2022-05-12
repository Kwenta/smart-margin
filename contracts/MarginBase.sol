// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MarginBase is MinimalProxyable {

    IERC20 public margin;

    constructor() MinimalProxyable() {
        // Note never used except for first CREATE
    }

    function initialize(address _marginAsset) external initOnce {
        margin = IERC20(_marginAsset);
        // Note the Ownable constructor is never when we create minimal proxies
        _transferOwnership(msg.sender);
    }

    function deposit(uint amount) public onlyOwner {
        margin.transferFrom(owner(), address(this), amount);
    }

    function withdraw(uint amount) external onlyOwner {
        margin.transfer(owner(), amount);
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
