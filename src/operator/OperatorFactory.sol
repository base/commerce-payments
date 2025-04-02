// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {LibClone} from "solady/utils/LibClone.sol";

import {Operator} from "./Operator.sol";

contract OperatorFactory {
    address immutable implementation;

    constructor() {
        implementation = address(new Operator(msg.sender));
    }

    function create(address owner, address[] calldata executors, bytes32 salt) external {
        address operator = LibClone.cloneDeterministic(implementation, salt);
        Operator(operator).initialize(owner, executors);
    }
}
