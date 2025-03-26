// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @notice Minimal contract for PaymentEscrow operations
/// @dev Enables batch execution and multiple executors for higher throughput potential and convenience
contract Operator is Ownable {
    address escrow;
    mapping(address executor => bool allowed) isExecutor;

    event ExecutorUpdated(address executor, bool allowed);

    constructor(address escrow_, address owner_, address[] memory executors) Ownable(owner_) {
        escrow = escrow_;
        for (uint256 i; i < executors.length; i++) {
            isExecutor[executors[i]] = true;
        }
    }

    modifier onlyExecutor() {
        if (msg.sender != address(this) && isExecutor[msg.sender]) revert();
        _;
    }

    function multicall(bytes[] calldata calls) external onlyExecutor {
        uint256 callsLen = calls.length;
        for (uint256 i; i < callsLen; i++) {
            address(this).call(calls[i]);
        }
    }

    function execute(bytes calldata data) external onlyExecutor {
        escrow.call(data);
    }

    function execute(address target, bytes calldata data) external onlyExecutor {
        target.call(data);
    }

    function execute(address target, uint256 value, bytes calldata data) external onlyExecutor {
        target.call{value: value}(data);
    }

    function updateExecutor(address executor, bool allowed) external onlyOwner {
        isExecutor[executor] = allowed;
        emit ExecutorUpdated(executor, allowed);
    }
}
