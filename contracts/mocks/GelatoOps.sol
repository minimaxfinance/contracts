// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IGelatoOps.sol";

contract GelatoOpsMock is IGelatoOps {
    function createTask(
        address execAddress,
        bytes4 execSelector,
        address resolverAddress,
        bytes calldata resolverData
    ) public returns (bytes32 task) {
        return 0;
    }

    function createTaskNoPrepayment(
        address execAddress,
        bytes4 execSelector,
        address resolverAddress,
        bytes calldata resolverData,
        address feeToken
    ) public returns (bytes32 task) {
        return 0;
    }

    function cancelTask(bytes32 taskId) public {}

    function getFeeDetails() external view returns (uint256, address) {
        return (0, address(0));
    }

    function gelato() external view returns (address payable) {
        return payable(address(0));
    }

    function taskTreasury() external view returns (address) {
        return address(0);
    }

    function getTaskId(
        address taskCreator,
        address execAddress,
        bytes4 selector,
        bool useTaskTreasuryFunds,
        address feeToken,
        bytes32 resolverHash
    ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getResolverHash(address resolverAddress, bytes memory resolverData) external pure returns (bytes32) {
        return bytes32(0);
    }
}
