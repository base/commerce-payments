// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @notice Minimal contract for PaymentEscrow operations
/// @dev Enables batch execution and multiple executors for higher throughput potential and convenience
contract Operator {
    address escrow;
    address owner;
    mapping(address executor => bool allowed) allowedExecutors;

    event ExecutorUpdated(address executor, bool allowed);

    constructor(address escrow_, address owner_, address[] memory executors) {
        escrow = escrow_;
        owner = owner_;
        for (uint256 i; i < executors.length; i++) {
            allowedExecutors[executors[i]] = true;
        }
    }

    function sendCalls(bytes[] calldata calls) external {
        if (!allowedExecutors[msg.sender]) revert();

        uint256 callsLen = calls.length;
        for (uint256 i; i < callsLen; i++) {
            escrow.call(calls[i]);
        }
    }

    function updateExecutor(address executor, bool allowed) external {
        if (msg.sender != owner) revert();

        allowedExecutors[executor] = allowed;
        emit ExecutorUpdated(executor, allowed);
    }
}
