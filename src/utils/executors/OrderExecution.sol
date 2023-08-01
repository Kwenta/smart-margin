// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IAccount {
    /// @param _conditionalOrderId: key for an active conditional order
    function executeConditionalOrder(uint256 _conditionalOrderId) external;

    /// @notice checker() is the Resolver for Gelato
    /// (see https://docs.gelato.network/developer-services/automate/guides/custom-logic-triggers/smart-contract-resolvers)
    /// @notice signal to a keeper that a conditional order is valid/invalid for execution
    /// @dev call reverts if conditional order Id does not map to a valid conditional order;
    /// ConditionalOrder.marketKey would be invalid
    /// @param _conditionalOrderId: key for an active conditional order
    /// @return canExec boolean that signals to keeper a conditional order can be executed by Gelato
    /// @return execPayload calldata for executing a conditional order
    function checker(uint256 _conditionalOrderId)
        external
        view
        returns (bool canExec, bytes memory execPayload);
}

interface IPerpsV2ExchangeRate {
    /// @notice fetches the Pyth oracle contract address from Synthetix
    /// @return Pyth contract
    function offchainOracle() external view returns (IPyth);
}

interface IPyth {
    /// @notice Update price feeds with given update messages.
    /// This method requires the caller to pay a fee in wei; the required fee can be computed by calling
    /// `getUpdateFee` with the length of the `updateData` array.
    /// Prices will be updated if they are more recent than the current stored prices.
    /// The call will succeed even if the update is not the most recent.
    /// @dev Reverts if the transferred fee is not sufficient or the updateData is invalid.
    /// @param updateData Array of price update data.
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /// @notice Returns the required fee to update an array of price updates.
    /// @param updateData Array of price update data.
    /// @return feeAmount The required fee in Wei.
    function getUpdateFee(bytes[] calldata updateData)
        external
        view
        returns (uint256 feeAmount);
}

/// @title utility contract for executing conditional orders
/// @notice this contract is untested and should be used with caution
/// @custom:auditor ignore this file
/// @author JaredBorders (jaredborders@pm.me)
contract OrderExecution {
    address internal immutable OWNER;
    IPerpsV2ExchangeRate internal immutable PERPS_V2_EXCHANGE_RATE;
    IPyth internal immutable ORACLE;

    error PythPriceUpdateFailed();
    error OnlyOwner();

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwner();
        _;
    }

    constructor(address _owner, address _perpsV2ExchangeRate) {
        OWNER = _owner;
        PERPS_V2_EXCHANGE_RATE = IPerpsV2ExchangeRate(_perpsV2ExchangeRate);
        ORACLE = PERPS_V2_EXCHANGE_RATE.offchainOracle();
    }

    /// @notice updates the Pyth oracle price feed and executes a batch of conditional orders
    /// @dev reverts if the Pyth price update fails
    /// @param priceUpdateData: array of price update data
    /// @param accounts: array of SM account addresses
    /// @param ids: array of conditional order Ids
    function updatePriceThenExecuteOrders(
        bytes[] calldata priceUpdateData,
        address[] calldata accounts,
        uint256[] calldata ids
    ) external payable {
        updatePythPrice(priceUpdateData);
        executeOrders(accounts, ids);
    }

    /// @dev updates the Pyth oracle price feed
    /// @dev refunds the caller any unused value not used to update feed
    /// @param priceUpdateData: array of price update data
    function updatePythPrice(bytes[] calldata priceUpdateData) public payable {
        uint256 fee = ORACLE.getUpdateFee(priceUpdateData);

        // try to update the price data (and pay the fee)
        /// @dev excess value is *not* automatically refunded
        /// and the caller must withdraw it manually
        try ORACLE.updatePriceFeeds{value: fee}(priceUpdateData) {}
        catch {
            revert PythPriceUpdateFailed();
        }
    }

    /// @dev executes a batch of conditional orders in reverse order (i.e. LIFO)
    /// @param accounts: array of SM account addresses
    /// @param ids: array of conditional order Ids
    function executeOrders(address[] calldata accounts, uint256[] calldata ids)
        public
    {
        uint256 i = accounts.length;
        do {
            unchecked {
                --i;
            }

            (bool canExec,) = IAccount(accounts[i]).checker(ids[i]);
            if (!canExec) continue; // skip to next order without reverting

            IAccount(accounts[i]).executeConditionalOrder(ids[i]);
        } while (i != 0);
    }

    /*//////////////////////////////////////////////////////////////
                      MODIFY CONTRACT ETH BALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice withdraws ETH from the contract to the _beneficiary
    /// @dev reverts if the transfer fails
    /// @param _beneficiary: address to send ETH to
    function withdrawEth(address payable _beneficiary) external onlyOwner {
        (bool success,) = _beneficiary.call{value: address(this).balance}("");
        assert(success);
    }

    receive() external payable {}
}
