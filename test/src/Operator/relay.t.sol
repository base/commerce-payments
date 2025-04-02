// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {OperatorBase} from "../../base/OperatorBase.sol";

import {Operator} from "../../../src/operator/Operator.sol";

contract RelayTest is OperatorBase {
    function test_relay(bytes32 id, bytes memory data, uint160 nonceKey) public {
        Operator.Operation[] memory operations = _getOperations(id, data);
        uint256 nonce = uint256(nonceKey); // no sequence needed
        bytes memory signature = _signOperations(operations, nonce);

        operator.relay(operations, nonce, executor, signature);
    }
}
