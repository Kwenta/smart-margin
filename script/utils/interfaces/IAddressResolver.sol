// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IAddressResolver {
    function getAddress(bytes32 name) external view returns (address);
}
