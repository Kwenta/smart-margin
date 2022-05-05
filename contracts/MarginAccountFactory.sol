// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyFactory.sol";
import "./CrossMarginBase.sol";

contract MarginAccountFactory is MinimalProxyFactory {

    string public version; // 0.1.0
    CrossMarginBase implementation;

    constructor(string memory _version) {
        version = _version;
        implementation = new CrossMarginBase();
    }

    function newAccount() external returns (address) {
        CrossMarginBase account = CrossMarginBase(_cloneAsMinimalProxy(address(implementation), "Creation failure"));
        account.initialize(/* @TODO: Initialize msg.sender as owner */);

        emit NewAccount(msg.sender, address(account));
        return address(account);
    }

    event NewAccount(address indexed owner, address account);

}