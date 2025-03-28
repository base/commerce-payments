// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {TokenCollector} from "./TokenCollector.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract Permit2TokenCollector is TokenCollector {
    IPermit2 public immutable permit2;

    constructor(address _permit2, address _paymentEscrow) TokenCollector(_paymentEscrow) {
        permit2 = IPermit2(_permit2);
    }

    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        (bytes memory signature) = abi.decode(collectorData, (bytes));
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: paymentDetails.token,
                    amount: paymentDetails.maxAmount
                }),
                nonce: uint256(paymentDetailsHash),
                deadline: paymentDetails.preApprovalExpiry
            }),
            ISignatureTransfer.SignatureTransferDetails({to: address(paymentEscrow), requestedAmount: amount}),
            paymentDetails.payer,
            signature
        );
    }
}
