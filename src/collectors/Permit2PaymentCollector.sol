// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {ERC6492SignatureHandler} from "./ERC6492SignatureHandler.sol";
import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

/// @title Permit2PaymentCollector
///
/// @notice Collect payments using Permit2 signatures
///
/// @author Coinbase, Shopify
contract Permit2PaymentCollector is TokenCollector, ERC6492SignatureHandler {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Permit2 singleton
    ISignatureTransfer public immutable permit2;

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    /// @param permit2_ Permit2 singleton
    /// @param multicall3_ Public Multicall3 singleton for safe ERC-6492 external calls
    constructor(address authCaptureEscrow_, address permit2_, address multicall3_)
        TokenCollector(authCaptureEscrow_)
        ERC6492SignatureHandler(multicall3_)
    {
        permit2 = ISignatureTransfer(permit2_);
    }

    /// @inheritdoc TokenCollector
    ///
    /// @dev Use Permit2 signature transfer to collect any ERC-20 from payers
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        permit2.permitTransferFrom({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: paymentInfo.token, amount: paymentInfo.maxAmount}),
                nonce: uint256(_getHashPayerAgnostic(paymentInfo)),
                deadline: paymentInfo.preApprovalExpiry
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({to: tokenStore, requestedAmount: amount}),
            owner: paymentInfo.payer,
            signature: _handleERC6492Signature(collectorData)
        });
    }
}
