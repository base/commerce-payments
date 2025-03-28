// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {TokenCollector} from "./TokenCollector.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract SpendPermissionTokenCollector is TokenCollector {
    SpendPermissionManager public immutable spendPermissionManager;

    error InvalidSignature();

    constructor(address _spendPermissionManager, address _paymentEscrow) TokenCollector(_paymentEscrow) {
        spendPermissionManager = SpendPermissionManager(payable(_spendPermissionManager));
    }

    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata hookData
    ) external override onlyPaymentEscrow {
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentDetails.payer,
            spender: address(this),
            token: paymentDetails.token,
            allowance: uint160(amount),
            period: type(uint48).max,
            start: 0,
            end: paymentDetails.preApprovalExpiry,
            salt: uint256(paymentDetailsHash),
            extraData: hex""
        });

        (bytes memory signature, MagicSpend.WithdrawRequest memory withdrawRequest) =
            abi.decode(hookData, (bytes, MagicSpend.WithdrawRequest));

        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, signature);
            if (!approved) revert InvalidSignature();
        }

        if (withdrawRequest.signature.length == 0) {
            spendPermissionManager.spend(permission, uint160(amount));
        } else {
            spendPermissionManager.spendWithWithdraw(permission, uint160(amount), withdrawRequest);
        }

        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), amount);
    }
}
