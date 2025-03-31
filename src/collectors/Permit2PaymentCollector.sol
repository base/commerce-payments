// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract Permit2PaymentCollector is TokenCollector {
    ISignatureTransfer public immutable permit2;

    constructor(address paymentEscrow_, address permit2_) TokenCollector(paymentEscrow_) {
        permit2 = ISignatureTransfer(permit2_);
    }

    /// @inheritdoc TokenCollector
    function getCollectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
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
