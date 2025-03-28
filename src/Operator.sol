// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @notice Minimal contract for PaymentEscrow operations
/// @dev Enables batch execution from multiple executors for optimal throughput and efficiency
contract Operator is Ownable {
    struct Call {
        bytes32 id;
        address target;
        bytes data;
    }

    mapping(address executor => bool allowed) public isExecutor;

    event ExecutorUpdated(address executor, bool allowed);
    event CallFailed(bytes32 callId, address executor);

    error InvalidExecutor(address executor);

    constructor(address owner_, address[] memory executors) Ownable(owner_) {
        for (uint256 i; i < executors.length; i++) {
            isExecutor[executors[i]] = true;
            emit ExecutorUpdated(executors[i], true);
        }
    }

    modifier onlyExecutor() {
        if (isExecutor[msg.sender]) revert InvalidExecutor(msg.sender);
        _;
    }

    function execute(Call calldata call) external onlyExecutor {
        _execute(call);
    }

    function execute(Call calldata calls) external onlyExecutor {
        uint256 len = calls.length;
        for (uint256 i; i < len; i++) {
            _execute(calls[i]);
        }
    }

    function _execute(Call calldata call) internal {
        (bool success, bytes memory res) = call.target.call(call.data);
        if (!success) emit CallFailed(call.id, msg.sender);
    }

    function updateExecutor(address executor, bool allowed) external onlyOwner {
        isExecutor[executor] = allowed;
        emit ExecutorUpdated(executor, allowed);
    }
}
