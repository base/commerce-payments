// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract ERC3009RefundTokenCollector is TokenCollector {
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    IMulticall3 public immutable multicall3;

    constructor(address _multicall3, address _paymentEscrow) TokenCollector(_paymentEscrow) {
        multicall3 = IMulticall3(_multicall3);
    }

    /// @inheritdoc TokenCollector
    function getCollectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Refund;
    }

    /// @inheritdoc TokenCollector
    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        address sponsor;
        uint48 deadline;
        uint256 salt;
        bytes memory signature;
        (sponsor, deadline, salt, signature) = abi.decode(collectorData, (address, uint48, uint256, bytes));

        signature = _handleERC6492Signature(signature);

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        // First receive the tokens to this contract
        IERC3009(paymentDetails.token).receiveWithAuthorization({
            from: sponsor,
            to: address(this),
            value: amount,
            validAfter: 0,
            validBefore: deadline,
            nonce: keccak256(abi.encode(paymentDetailsHash, salt)),
            signature: signature
        });

        // Then transfer them to the escrow
        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), amount);
    }

    /// @notice Parse and process ERC-6492 signatures
    function _handleERC6492Signature(bytes memory signature) internal returns (bytes memory) {
        // early return if signature less than 32 bytes
        if (signature.length < 32) return signature;

        // early return if signature suffix not ERC-6492 magic value
        bytes32 suffix;
        assembly {
            suffix := mload(add(add(signature, 32), sub(mload(signature), 32)))
        }
        if (suffix != ERC6492_MAGIC_VALUE) return signature;

        // parse inner signature from ERC-6492 format
        address target;
        bytes memory prepareData;
        bytes memory erc6492Data = new bytes(signature.length - 32);
        for (uint256 i = 0; i < signature.length - 32; i++) {
            erc6492Data[i] = signature[i];
        }
        (target, prepareData, signature) = abi.decode(erc6492Data, (address, bytes, bytes));

        // construct call to target with prepareData
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = IMulticall3.Call(target, prepareData);
        multicall3.tryAggregate({requireSuccess: false, calls: calls});

        return signature;
    }
}
