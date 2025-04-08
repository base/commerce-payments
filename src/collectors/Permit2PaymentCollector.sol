// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title Permit2PaymentCollector
/// @notice Collect payments using Permit2 signatures
/// @author Coinbase
contract Permit2PaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    ISignatureTransfer public immutable permit2;

    constructor(address paymentEscrow_, address permit2_) TokenCollector(paymentEscrow_) {
        permit2 = ISignatureTransfer(permit2_);
    }

    /// @inheritdoc TokenCollector
    /// @dev Use Permit2 signature transfer to collect any ERC-20 from payers
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata signature
    ) external override onlyPaymentEscrow {
        address treasury = paymentEscrow.getOperatorTreasury(paymentInfo.operator);
        permit2.permitTransferFrom({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: paymentInfo.token, amount: paymentInfo.maxAmount}),
                nonce: uint256(paymentInfoHash),
                deadline: paymentInfo.preApprovalExpiry
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({to: treasury, requestedAmount: amount}),
            owner: paymentInfo.payer,
            signature: signature
        });
    }
}
