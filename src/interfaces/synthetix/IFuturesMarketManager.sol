// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IFuturesMarketManager {
    function markets(uint256 index, uint256 pageSize) external view returns (address[] memory);

    function markets(uint256 index, uint256 pageSize, bool proxiedMarkets)
        external
        view
        returns (address[] memory);

    function numMarkets() external view returns (uint256);

    function numMarkets(bool proxiedMarkets) external view returns (uint256);

    function allMarkets() external view returns (address[] memory);

    function allMarkets(bool proxiedMarkets) external view returns (address[] memory);

    function marketForKey(bytes32 marketKey) external view returns (address);

    function marketsForKeys(bytes32[] calldata marketKeys)
        external
        view
        returns (address[] memory);

    function totalDebt() external view returns (uint256 debt, bool isInvalid);
}
