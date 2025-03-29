// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract SpendPermissionTokenCollector is TokenCollector {
    SpendPermissionManager public immutable spendPermissionManager;

    error InvalidSignature();

    constructor(address paymentEscrow_, address spendPermissionManager_) TokenCollector(paymentEscrow_) {
        spendPermissionManager = SpendPermissionManager(payable(spendPermissionManager_));
    }

    /// @inheritdoc TokenCollector
    function getCollectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
    }

    /// @inheritdoc TokenCollector
    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentDetails.payer,
            spender: address(this),
            token: paymentDetails.token,
            allowance: uint160(amount),
            period: type(uint48).max,
            start: 0,
            end: paymentDetails.preApprovalExpiry,
            salt: uint256(paymentEscrow.getHash(paymentDetails)),
            extraData: hex""
        });

        (bytes memory signature, bytes memory encodedWithdrawRequest) = abi.decode(collectorData, (bytes, bytes));

        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, signature);
            if (!approved) revert InvalidSignature();
        }

        if (encodedWithdrawRequest.length == 0) {
            spendPermissionManager.spend(permission, uint160(amount));
        } else {
            MagicSpend.WithdrawRequest memory withdrawRequest =
                abi.decode(encodedWithdrawRequest, (MagicSpend.WithdrawRequest));
            spendPermissionManager.spendWithWithdraw(permission, uint160(amount), withdrawRequest);
        }

        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), amount);
    }
}
