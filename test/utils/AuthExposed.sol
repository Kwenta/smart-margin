// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Auth} from "src/Account.sol";

contract AuthExposed is Auth {
    constructor(address _owner) Auth(_owner) {}
}
