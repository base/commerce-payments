// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {MockTarget} from "../mocks/MockTarget.sol";

import {Operator} from "../../src/operator/Operator.sol";
import {OperatorFactory} from "../../src/operator/OperatorFactory.sol";

contract OperatorBase is Test {
    OperatorFactory operatorFactory;
    address owner;
    uint256 executorPk;
    address executor;
    Operator operator;
    address mockTarget;

    function setUp() public virtual {
        operatorFactory = new OperatorFactory();
        mockTarget = address(new MockTarget());

        owner = vm.addr(10);
        vm.label(owner, "owner");
        executorPk = 0xbeef;
        executor = vm.addr(executorPk);
        vm.label(executor, "executor");

        address[] memory executors = new address[](1);
        executors[0] = executor;

        operator = operatorFactory.create(owner, executors, 0);
    }

    function _getOperations(bytes32 id, bytes memory data) internal view returns (Operator.Operation[] memory) {
        Operator.Operation[] memory operations = new Operator.Operation[](1);
        operations[0] = Operator.Operation(id, mockTarget, data);
        return operations;
    }

    function _signOperation(Operator.Operation memory operation, uint256 nonce) internal view returns (bytes memory) {
        Operator.Operation[] memory operations = new Operator.Operation[](1);
        operations[0] = operation;
        return _signOperations(operations, nonce);
    }

    function _signOperations(Operator.Operation[] memory operations, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 relayHash = operator.getRelayHash(operations, nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(executorPk, relayHash);
        return abi.encodePacked(r, s, v);
    }
}
