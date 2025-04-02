// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {OperatorBase} from "../../base/OperatorBase.sol";

import {Operator} from "../../../src/operator/Operator.sol";

contract ExecuteTest is OperatorBase {
    function test_execute(bytes32 id, bytes memory data) public {
        Operator.Operation[] memory operations = _getOperations(id, data);

        vm.prank(executor);
        operator.execute(operations);
    }
}
