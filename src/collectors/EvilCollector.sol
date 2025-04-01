// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title EvilCollector
contract EvilCollector is TokenCollector {
    bool private reenter;

    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {
        reenter = true;
    }

    /// @inheritdoc TokenCollector
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        if (reenter) {
            reenter = false;

            PaymentEscrow.PaymentInfo memory nextPaymentInfo = PaymentEscrow.PaymentInfo({
                operator: address(this),
                payer: address(this),
                receiver: address(this),
                token: paymentInfo.token,
                maxAmount: paymentInfo.maxAmount,
                preApprovalExpiry: paymentInfo.preApprovalExpiry,
                authorizationExpiry: paymentInfo.authorizationExpiry,
                refundExpiry: paymentInfo.refundExpiry,
                minFeeBps: paymentInfo.minFeeBps,
                maxFeeBps: paymentInfo.maxFeeBps,
                feeReceiver: paymentInfo.feeReceiver,
                salt: paymentInfo.salt + 1
            });

            paymentEscrow.charge(nextPaymentInfo, amount, address(this), collectorData, 0, address(0));
        } else {
            reenter = true;
            SafeTransferLib.safeTransfer(paymentInfo.token, address(paymentEscrow), amount);
        }
    }
}
