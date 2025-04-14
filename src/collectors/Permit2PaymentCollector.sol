// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title Permit2PaymentCollector
/// @notice Collect payments using Permit2 signatures
/// @author Coinbase
contract Permit2PaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Permit2 singleton
    ISignatureTransfer public immutable permit2;

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    /// @param permit2_ Permit2 singleton
    constructor(address paymentEscrow_, address permit2_) TokenCollector(paymentEscrow_) {
        permit2 = ISignatureTransfer(permit2_);
    }

    /// @inheritdoc TokenCollector
    /// @dev Use Permit2 signature transfer to collect any ERC-20 from payers
    function _collectTokens(PaymentEscrow.PaymentInfo calldata paymentInfo, uint256 amount, bytes calldata signature)
        internal
        override
    {
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);
        permit2.permitTransferFrom({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: paymentInfo.token, amount: paymentInfo.maxAmount}),
                nonce: uint256(_getHashPayerAgnostic(paymentInfo)),
                deadline: paymentInfo.preApprovalExpiry
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({to: tokenStore, requestedAmount: amount}),
            owner: paymentInfo.payer,
            signature: signature
        });
    }
}
