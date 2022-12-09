// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice This is used for testing -- do not use in prod
contract MintableERC20 is ERC20 {
    constructor(address account, uint amount) ERC20("", "") {
        mint(account, amount);
    } 

    function mint(address account, uint amount) public {
        _mint(account, amount);
    }
}