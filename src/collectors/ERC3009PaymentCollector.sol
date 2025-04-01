// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title ERC3009PaymentCollector
/// @notice Collect payments using ERC-3009 ReceiveWithAuthorization signatures
/// @author Coinbase
contract ERC3009PaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;

    IMulticall3 public immutable multicall3;

    constructor(address paymentEscrow_, address multicall3_) TokenCollector(paymentEscrow_) {
        multicall3 = IMulticall3(multicall3_);
    }

    /// @inheritdoc TokenCollector
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        // apply ERC-6492 preparation call if present
        bytes memory signature = _handleERC6492Signature(collectorData);

        // pull tokens into this contract
        IERC3009(paymentInfo.token).receiveWithAuthorization({
            from: paymentInfo.payer,
            to: address(this),
            value: paymentInfo.maxAmount,
            validAfter: 0,
            validBefore: paymentInfo.preApprovalExpiry,
            nonce: paymentInfoHash,
            signature: signature
        });

        // return excess tokens to buyer
        uint256 excess = paymentInfo.maxAmount - amount;
        if (excess > 0) {
            SafeTransferLib.safeTransfer(paymentInfo.token, paymentInfo.payer, excess);
        }

        // transfer tokens to escrow
        SafeTransferLib.safeTransfer(paymentInfo.token, address(paymentEscrow), amount);
    }

    /// @notice Parse and process ERC-6492 signatures
    /// @param signature User-provided signature
    /// @return innerSignature Remaining signature after ERC-6492 parsing
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
        bytes memory erc6492Data = new bytes(signature.length - 32);
        for (uint256 i = 0; i < signature.length - 32; i++) {
            erc6492Data[i] = signature[i];
        }
        address prepareTarget;
        bytes memory prepareData;
        (prepareTarget, prepareData, signature) = abi.decode(erc6492Data, (address, bytes, bytes));

        // construct call to prepareTarget with prepareData
        // calls made through a neutral public contract to prevent abuse of using this contract as sender
        IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
        calls[0] = IMulticall3.Call(prepareTarget, prepareData);
        multicall3.tryAggregate({requireSuccess: false, calls: calls});

        return signature;
    }
}
