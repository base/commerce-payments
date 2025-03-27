// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract Permit2PullTokensHook is IPullTokensHook {
    IPermit2 public immutable permit2;

    constructor(address _permit2, address _paymentEscrow) IPullTokensHook(_paymentEscrow) {
        permit2 = IPermit2(_permit2);
    }

    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature,
        bytes calldata
    ) external override onlyPaymentEscrow {
        permit2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: paymentDetails.token, amount: value}),
                nonce: uint256(paymentDetailsHash),
                deadline: paymentDetails.preApprovalExpiry
            }),
            ISignatureTransfer.SignatureTransferDetails({to: address(paymentEscrow), requestedAmount: value}),
            paymentDetails.payer,
            signature
        );
    }
}
