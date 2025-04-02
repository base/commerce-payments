// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";

/// @title Operator
/// @notice Minimal contract for operating onchain systems at scale
/// @dev Enables batch execution from multiple executors for optimal throughput and efficiency
/// @dev Enables relaying for convenience from any party
contract Operator is Ownable2Step, EIP712 {
    struct Operation {
        bytes32 id;
        address target;
        bytes data;
    }

    bytes32 public constant OPERATION_TYPEHASH = keccak256("Operation(bytes32 id,address target,bytes data)");
    bytes32 public constant OPERATION_BATCH_TYPEHASH =
        keccak256("OperationBatch(Operation[] operations,uint256 nonce)Operation(bytes32 id,address target,bytes data)");

    mapping(address executor => bool allowed) public isExecutor;
    mapping(uint256 nonceKey => uint256 nonceSequence) public nonces;

    event NonceUsed(uint160 nonceKey, uint96 nonceSequence);
    event OperationFailed(bytes32 id, address executor, bytes error);
    event ExecutorUpdated(address executor, bool allowed);

    error InvalidExecutor(address executor);
    error InvalidNonce(uint160 nonceKey, uint96 nonceSequence, uint96 expectedSequence);
    error InvalidSignature();

    /// @dev Needed to provide initialOwner for compiler, immediately revokes in constructor for singleton implementation
    constructor(address initialOwner) Ownable(initialOwner) {
        _transferOwnership(address(0));
    }

    function initialize(address owner_, address[] calldata executors) external {
        if (owner() != address(0)) revert OwnableInvalidOwner(address(0));
        _transferOwnership(owner_);

        for (uint256 i; i < executors.length; i++) {
            isExecutor[executors[i]] = true;
            emit ExecutorUpdated(executors[i], true);
        }
    }

    function execute(Operation[] calldata operations) external {
        if (!isExecutor[msg.sender]) revert InvalidExecutor(msg.sender);

        uint256 len = operations.length;
        for (uint256 i; i < len; i++) {
            _execute(operations[i]);
        }
    }

    function relay(Operation[] calldata operations, uint256 nonce, address executor, bytes calldata signature)
        external
    {
        if (!isExecutor[executor]) revert InvalidExecutor(msg.sender);

        uint160 nonceKey = uint160(nonce);
        uint96 nonceSequence = uint96(nonces[nonceKey]);
        if (uint96(nonce >> 160) != nonceSequence) revert InvalidNonce(nonceKey, uint96(nonce >> 160), nonceSequence);
        nonces[nonceKey] += 1;
        emit NonceUsed(nonceKey, nonceSequence);

        bytes32 relayHash = getRelayHash(operations, nonce);
        if (!SignatureCheckerLib.isValidSignatureNow(executor, relayHash, signature)) revert InvalidSignature();

        uint256 len = operations.length;
        for (uint256 i; i < len; i++) {
            _execute(operations[i]);
        }
    }

    function updateExecutor(address executor, bool allowed) external onlyOwner {
        isExecutor[executor] = allowed;
        emit ExecutorUpdated(executor, allowed);
    }

    function getRelayHash(Operation[] calldata operations, uint256 nonce) public view returns (bytes32) {
        uint256 len = operations.length;
        bytes32[] memory operationHashes = new bytes32[](len);
        for (uint256 i; i < len; i++) {
            operationHashes[i] = keccak256(
                abi.encode(OPERATION_TYPEHASH, operations[i].id, operations[i].target, keccak256(operations[i].data))
            );
        }
        bytes32 structHash =
            keccak256(abi.encode(OPERATION_BATCH_TYPEHASH, keccak256(abi.encode(operationHashes)), nonce));

        return _hashTypedData(structHash);
    }

    function renounceOwnership() public pure override {
        revert();
    }

    function _execute(Operation calldata operation) internal {
        (bool success, bytes memory res) = operation.target.call(operation.data);
        if (!success) emit OperationFailed(operation.id, msg.sender, res);
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        return ("Operator", "1");
    }
}
