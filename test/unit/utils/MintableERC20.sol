// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice This is used for testing -- do not use in prod
contract MintableERC20 is ERC20 {
    constructor(address account, uint256 amount) ERC20("", "") {
        mint(account, amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
