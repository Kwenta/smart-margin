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

/// @title Utility contract for executing conditional orders
/// @notice This contract is untested and should be used with caution
/// @custom:auditor ignore
/// @author JaredBorders (jaredborders@pm.me)
contract OrderExecution {
    IPerpsV2ExchangeRate public immutable PERPS_V2_EXCHANGE_RATE;

    error PythPriceUpdateFailed();

    constructor(address _perpsV2ExchangeRate) {
        PERPS_V2_EXCHANGE_RATE = IPerpsV2ExchangeRate(_perpsV2ExchangeRate);
    }

    /// @dev updates the Pyth oracle price feed and refunds the caller any unused value
    /// not used to update feed
    function updatePythPrice(bytes[] calldata priceUpdateData) public payable {
        /// @custom:optimization oracle could be immutable if we can guarantee it will never change
        IPyth oracle = PERPS_V2_EXCHANGE_RATE.offchainOracle();

        // determine fee amount to pay to Pyth for price update
        uint256 fee = oracle.getUpdateFee(priceUpdateData);

        // try to update the price data (and pay the fee)
        try oracle.updatePriceFeeds{value: fee}(priceUpdateData) {}
        catch {
            revert PythPriceUpdateFailed();
        }

        uint256 refund = msg.value - fee;
        if (refund > 0) {
            // refund caller the unused value
            (bool success,) = msg.sender.call{value: refund}("");
            assert(success);
        }
    }

    /// @dev executes a batch of conditional orders in reverse order (i.e. LIFO)
    function executeOrders(address[] calldata accounts, uint256[] calldata ids)
        public
    {
        assert(accounts.length > 0);
        assert(accounts.length == ids.length);

        uint256 i = accounts.length;
        do {
            unchecked {
                --i;
            }

            /**
             * @custom:logic could ensure onchain order can be executed via call to `checker`
             *
             * (bool canExec,) = IAccount(accounts[i]).checker(ids[i]);
             * assert(canExec);
             *
             */

            IAccount(accounts[i]).executeConditionalOrder(ids[i]);
        } while (i != 0);
    }

    function updatePriceThenExecuteOrders(
        bytes[] calldata priceUpdateData,
        address[] calldata accounts,
        uint256[] calldata ids
    ) external payable {
        updatePythPrice(priceUpdateData);
        executeOrders(accounts, ids);
    }
}
