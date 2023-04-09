// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IFuturesMarketManager {
    function marketForKey(bytes32 marketKey) external view returns (address);
}
