// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {LibClone} from "solady/utils/LibClone.sol";

import {Operator} from "./Operator.sol";

/// @title OperatorFactory
/// @notice Minimal contract for operating onchain systems at scale
/// @dev Enables batch execution from multiple executors for optimal throughput and efficiency
/// @dev Enables relaying for convenience from any party
contract OperatorFactory {
    address public immutable implementation;

    event OperatorCreated(address operator);

    constructor() {
        implementation = address(new Operator(msg.sender));
    }

    function create(address owner, address[] calldata executors, uint256 salt) external returns (Operator) {
        Operator operator = Operator(LibClone.cloneDeterministic(implementation, bytes32(salt)));
        emit OperatorCreated(address(operator));
        operator.initialize(owner, executors);
        return operator;
    }
}
