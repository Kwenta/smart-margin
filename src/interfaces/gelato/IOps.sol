// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IOps {
    /**
     * @notice Whitelisted modules that are available for users to customise conditions and specifications of their tasks.
     *
     * @param RESOLVER Use dynamic condition & input data for execution. {See ResolverModule.sol}
     * @param TIME Repeated execution of task at a specified timing and interval. {See TimeModule.sol}
     * @param PROXY Creates a dedicated caller (msg.sender) to be used when executing the task. {See ProxyModule.sol}
     * @param SINGLE_EXEC Task is cancelled after one execution. {See SingleExecModule.sol}
     */
    enum Module {
        RESOLVER,
        TIME,
        PROXY,
        SINGLE_EXEC
    }

    /**
     * @notice Struct to contain modules and their relative arguments that are used for task creation.
     *
     * @param modules List of selected modules.
     * @param args Arguments of modules if any. Pass "0x" for modules which does not require args {See encodeModuleArg}
     */
    struct ModuleData {
        Module[] modules;
        bytes[] args;
    }

    /**
     * @notice Struct for time module.
     *
     * @param nextExec Time when the next execution should occur.
     * @param interval Time interval between each execution.
     */
    struct Time {
        uint128 nextExec;
        uint128 interval;
    }

    /**
     * @notice Initiates a task with conditions which Gelato will monitor and execute when conditions are met.
     *
     * @param execAddress Address of contract that should be called by Gelato.
     * @param execData Execution data to be called with / function selector if execution data is yet to be determined.
     * @param moduleData Conditional modules that will be used.
     * @param feeToken Address of token to be used as payment. Use address(0) if TaskTreasury is being used, 0xeeeeee... for ETH or native tokens.
     *
     * @return taskId Unique hash of the task created.
     */
    function createTask(
        address execAddress,
        bytes calldata execData,
        ModuleData calldata moduleData,
        address feeToken
    ) external returns (bytes32 taskId);

    /**
     * @notice Terminates a task that was created and Gelato can no longer execute it.
     *
     * @param taskId Unique hash of the task that is being cancelled. {See LibTaskId-getTaskId}
     */
    function cancelTask(bytes32 taskId) external;

    /**
     * @notice Execution API called by Gelato.
     *
     * @param taskCreator The address which created the task.
     * @param execAddress Address of contract that should be called by Gelato.
     * @param execData Execution data to be called with / function selector if execution data is yet to be determined.
     * @param moduleData Conditional modules that will be used.
     * @param txFee Fee paid to Gelato for execution, deducted on the TaskTreasury or transfered to Gelato.
     * @param feeToken Token used to pay for the execution. ETH = 0xeeeeee...
     * @param useTaskTreasuryFunds If taskCreator's balance on TaskTreasury should pay for the tx.
     * @param revertOnFailure To revert or not if call to execAddress fails. (Used for off-chain simulations)
     */
    function exec(
        address taskCreator,
        address execAddress,
        bytes memory execData,
        ModuleData calldata moduleData,
        uint256 txFee,
        address feeToken,
        bool useTaskTreasuryFunds,
        bool revertOnFailure
    ) external;

    /**
     * @notice Sets the address of task modules. Only callable by proxy admin.
     *
     * @param modules List of modules to be set
     * @param moduleAddresses List of addresses for respective modules.
     */
    function setModule(
        Module[] calldata modules,
        address[] calldata moduleAddresses
    ) external;

    /**
     * @notice Helper function to query fee and feeToken to be used for payment. (For executions which pays itself)
     *
     * @return uint256 Fee amount to be paid.
     * @return address Token to be paid. (Determined and passed by taskCreator during createTask)
     */
    function getFeeDetails() external view returns (uint256, address);

    /**
     * @notice Helper func to query all open tasks by a task creator.
     *
     * @param taskCreator Address of task creator to query.
     *
     * @return bytes32[] List of taskIds created.
     */
    function getTaskIdsByUser(address taskCreator)
        external
        view
        returns (bytes32[] memory);

    /**
     * @notice Helper function to compute task id with module arguments
     *
     * @param taskCreator The address which created the task.
     * @param execAddress Address of contract that will be called by Gelato.
     * @param execSelector Signature of the function which will be called by Gelato.
     * @param moduleData  Conditional modules that will be used. {See LibDataTypes-ModuleData}
     * @param feeToken Address of token to be used as payment. Use address(0) if TaskTreasury is being used, 0xeeeeee... for ETH or native tokens.
     */
    function getTaskId(
        address taskCreator,
        address execAddress,
        bytes4 execSelector,
        ModuleData memory moduleData,
        address feeToken
    ) external pure returns (bytes32 taskId);
}
