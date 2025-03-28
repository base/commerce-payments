// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {TokenCollector} from "./TokenCollector.sol";
import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract ERC3009TokenCollector is TokenCollector {
    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    IMulticall3 public immutable multicall3;

    constructor(address _multicall3, address _paymentEscrow) TokenCollector(_paymentEscrow) {
        multicall3 = IMulticall3(_multicall3);
    }

    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        bytes memory signature = abi.decode(collectorData, (bytes));
        bytes memory innerSignature = signature;
        // Check for ERC-6492 signature format
        bytes32 magicValue;
        if (signature.length >= 32) {
            assembly {
                magicValue := mload(add(add(signature, 32), sub(mload(signature), 32)))
            }
        }

        if (signature.length >= 32 && magicValue == ERC6492_MAGIC_VALUE) {
            // parse inner signature from ERC-6492 format
            address target;
            bytes memory prepareData;
            bytes memory erc6492Data = new bytes(signature.length - 32);
            for (uint256 i = 0; i < signature.length - 32; i++) {
                erc6492Data[i] = signature[i];
            }
            (target, prepareData, innerSignature) = abi.decode(erc6492Data, (address, bytes, bytes));

            // construct call to target with prepareData
            IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
            calls[0] = IMulticall3.Call(target, prepareData);
            multicall3.tryAggregate({requireSuccess: false, calls: calls});
        }

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        // First receive the tokens to this contract
        IERC3009(paymentDetails.token).receiveWithAuthorization({
            from: paymentDetails.payer,
            to: address(this),
            value: paymentDetails.maxAmount,
            validAfter: 0,
            validBefore: paymentDetails.preApprovalExpiry,
            nonce: paymentDetailsHash,
            signature: innerSignature
        });

        // Return excess funds to buyer
        uint256 excessFunds = paymentDetails.maxAmount - amount;
        if (excessFunds > 0) {
            SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, excessFunds);
        }

        // Then transfer them to the escrow
        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), amount);
    }
}
