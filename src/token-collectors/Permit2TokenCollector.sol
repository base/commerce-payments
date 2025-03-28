// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract Permit2TokenCollector is TokenCollector {
    ISignatureTransfer public immutable permit2;

    constructor(address _permit2, address _paymentEscrow) TokenCollector(_paymentEscrow) {
        permit2 = ISignatureTransfer(_permit2);
    }

    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata signature
    ) external override onlyPaymentEscrow {
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: paymentDetails.token,
                    amount: paymentDetails.maxAmount
                }),
                nonce: uint256(paymentEscrow.getHash(paymentDetails)),
                deadline: paymentDetails.preApprovalExpiry
            }),
            ISignatureTransfer.SignatureTransferDetails({to: address(paymentEscrow), requestedAmount: amount}),
            paymentDetails.payer,
            signature
        );
    }
}
