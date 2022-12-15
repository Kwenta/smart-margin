// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMarginAccountFactory.sol";
import "./IMarginAccountFactoryStorage.sol";
import "../MarginBase.sol";

/// @title Kwenta MarginAccountFactory Interface
/// @author JaredBorders (jaredborders@proton.me)
interface IMarginAccountFactory {
    function VERSION() external view returns (string memory);

    function addressResolver() external view returns (address);

    function implementation() external view returns (MarginBase);

    function marginAsset() external view returns (IERC20);

    function marginBaseSettings() external view returns (address);

    function newAccount() external returns (address payable accountAddress);

    function ops() external view returns (address payable);

    function store() external view returns (IMarginAccountFactoryStorage);
}
