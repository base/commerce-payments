// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magic-spend/MagicSpend.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract SpendPermissionPullTokensHook is IPullTokensHook {
    SpendPermissionManager public immutable spendPermissionManager;
    PaymentEscrow public immutable paymentEscrow;

    error InvalidSignature();
    error OnlyPaymentEscrow();

    constructor(address _spendPermissionManager, address _paymentEscrow) {
        spendPermissionManager = SpendPermissionManager(payable(_spendPermissionManager));
        paymentEscrow = PaymentEscrow(_paymentEscrow);
    }

    modifier onlyPaymentEscrow() {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _;
    }

    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature,
        bytes calldata hookData
    ) external override onlyPaymentEscrow {
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentDetails.payer,
            spender: address(this),
            token: paymentDetails.token,
            allowance: uint160(paymentDetails.value),
            period: type(uint48).max,
            start: 0,
            end: paymentDetails.preApprovalExpiry,
            salt: uint256(paymentDetailsHash),
            extraData: hex""
        });

        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, signature);
            if (!approved) revert InvalidSignature();
        }

        if (hookData.length == 0) {
            spendPermissionManager.spend(permission, uint160(value));
        } else {
            spendPermissionManager.spendWithWithdraw(
                permission, uint160(value), abi.decode(hookData, (MagicSpend.WithdrawRequest))
            );
        }

        SafeTransferLib.safeTransfer(paymentDetails.token, address(paymentEscrow), value);
    }
}
