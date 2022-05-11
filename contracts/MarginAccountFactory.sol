// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyFactory.sol";
import "./MarginBase.sol";

contract MarginAccountFactory is MinimalProxyFactory {

    string public version; // 0.1.0
    MarginBase public implementation;

    constructor(string memory _version) {
        version = _version;
        implementation = new MarginBase();
    }

    function newAccount() external returns (address) {
        MarginBase account = MarginBase(_cloneAsMinimalProxy(address(implementation), "Creation failure"));
        account.initialize();
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, address(account));
        return address(account);
    }

    event NewAccount(address indexed owner, address account);

}