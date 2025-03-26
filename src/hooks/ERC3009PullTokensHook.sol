// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {IERC3009} from "../interfaces/IERC3009.sol";
import {IMulticall3} from "../interfaces/IMulticall3.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract ERC3009PullTokensHook is IPullTokensHook {
    error OnlyPaymentEscrow();

    bytes32 public constant ERC6492_MAGIC_VALUE = 0x6492649264926492649264926492649264926492649264926492649264926492;
    IMulticall3 public immutable multicall3;
    PaymentEscrow public immutable paymentEscrow;

    modifier onlyPaymentEscrow() {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _;
    }

    constructor(address _multicall3, address _paymentEscrow) {
        multicall3 = IMulticall3(_multicall3);
        paymentEscrow = PaymentEscrow(_paymentEscrow);
    }

    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature,
        bytes calldata
    ) external override onlyPaymentEscrow {
        bytes memory innerSignature = signature;
        if (signature.length >= 32 && bytes32(signature[signature.length - 32:]) == ERC6492_MAGIC_VALUE) {
            // parse inner signature from ERC-6492 format
            address target;
            bytes memory prepareData;
            (target, prepareData, innerSignature) =
                abi.decode(signature[0:signature.length - 32], (address, bytes, bytes));

            // construct call to target with prepareData
            IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
            calls[0] = IMulticall3.Call(target, prepareData);
            multicall3.tryAggregate({requireSuccess: false, calls: calls});
        }

        // First receive the tokens to this contract
        IERC3009(paymentDetails.token).receiveWithAuthorization({
            from: paymentDetails.payer,
            to: address(this),
            value: paymentDetails.value,
            validAfter: 0,
            validBefore: paymentDetails.preApprovalExpiry,
            nonce: paymentDetailsHash,
            signature: innerSignature
        });

        // Return excess funds to buyer
        uint256 excessFunds = paymentDetails.value - value;
        if (excessFunds > 0) {
            SafeTransferLib.safeTransfer(paymentDetails.token, paymentDetails.payer, excessFunds);
        }

        // Then transfer them to the escrow
        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), value);
    }
}
