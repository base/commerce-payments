// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract SpendPermissionPullTokensHook is IPullTokensHook {
    SpendPermissionManager public immutable spendPermissionManager;

    error InvalidSignature();

    constructor(address _spendPermissionManager) {
        spendPermissionManager = SpendPermissionManager(payable(_spendPermissionManager));
    }

    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature
    ) external override {
        (bytes memory sig, bytes memory encodedWithdraw) = abi.decode(signature, (bytes, bytes));

        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentDetails.payer,
            spender: msg.sender,
            token: paymentDetails.token,
            allowance: uint160(value),
            period: type(uint48).max,
            start: 0,
            end: paymentDetails.preApprovalExpiry,
            salt: uint256(paymentDetailsHash),
            extraData: hex""
        });

        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, sig);
            if (!approved) revert InvalidSignature();
        }

        if (encodedWithdraw.length == 0) {
            spendPermissionManager.spend(permission, uint160(value));
        } else {
            spendPermissionManager.spendWithWithdraw(
                permission, uint160(value), abi.decode(encodedWithdraw, (MagicSpend.WithdrawRequest))
            );
        }

        SafeTransferLib.safeTransfer(paymentDetails.token, msg.sender, value);
    }
}
