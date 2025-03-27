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

    constructor(address _spendPermissionManager, address _paymentEscrow) IPullTokensHook(_paymentEscrow) {
        spendPermissionManager = SpendPermissionManager(payable(_spendPermissionManager));
    }

    function pullTokens(PaymentEscrow.PullTokensData memory pullTokensData) external override onlyPaymentEscrow {
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: pullTokensData.payer,
            spender: address(this),
            token: pullTokensData.token,
            allowance: uint160(pullTokensData.amount),
            period: type(uint48).max,
            start: 0,
            end: pullTokensData.preApprovalExpiry,
            salt: uint256(pullTokensData.nonce),
            extraData: hex""
        });

        if (pullTokensData.signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, pullTokensData.signature);
            if (!approved) revert InvalidSignature();
        }

        if (pullTokensData.hookData.length == 0) {
            spendPermissionManager.spend(permission, uint160(pullTokensData.amount));
        } else {
            spendPermissionManager.spendWithWithdraw(
                permission,
                uint160(pullTokensData.amount),
                abi.decode(pullTokensData.hookData, (MagicSpend.WithdrawRequest))
            );
        }

        SafeTransferLib.safeTransfer(pullTokensData.token, address(paymentEscrow), pullTokensData.amount);
    }
}
