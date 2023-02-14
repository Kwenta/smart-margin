// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IOps {
    event TaskCreated(
        address taskCreator,
        address execAddress,
        bytes4 selector,
        address resolverAddress,
        bytes32 taskId,
        bytes resolverData,
        bool useTaskTreasuryFunds,
        address feeToken,
        bytes32 resolverHash
    );

    event TaskCancelled(bytes32 taskId, address taskCreator);

    event ExecSuccess(
        uint256 indexed txFee,
        address indexed feeToken,
        address indexed execAddress,
        bytes execData,
        bytes32 taskId,
        bool callSuccess
    );

    function exec(
        uint256 _txFee,
        address _feeToken,
        address _taskCreator,
        bool _useTaskTreasuryFunds,
        bool _revertOnFailure,
        bytes32 _resolverHash,
        address _execAddress,
        bytes calldata _execData
    ) external;
    
    function gelato() external view returns (address payable);

    /// @notice create a task without prepayment
    /// @param _execAddress: Address of the contract to be called
    /// @param _execSelector: Selector of the function to be called
    /// @param _resolverAddress: checker (resolver) address
    /// @param _resolverData: data to be passed to the resolver
    /// @param _feeToken: address of the token to be used for the fee
    /// @return task Gelato task id
    function createTaskNoPrepayment(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData,
        address _feeToken
    ) external returns (bytes32 task);

    /// @notice cancel a task 
    /// @param _taskId: Gelato task id
    function cancelTask(bytes32 _taskId) external;

    function getFeeDetails() external view returns (uint256, address);

    function getResolverHash(
        address _resolverAddress,
        bytes memory _resolverData
    ) external pure returns (bytes32);

    function taskCreator(bytes32 _taskId) external view returns (address);
}
