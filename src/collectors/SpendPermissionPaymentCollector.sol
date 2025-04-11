// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title SpendPermissionPaymentCollector
/// @notice Collect payments using Spend Permissions
/// @author Coinbase
contract SpendPermissionPaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    SpendPermissionManager public immutable spendPermissionManager;

    /// @notice Spend permission approval failed
    error SpendPermissionApprovalFailed();

    constructor(address paymentEscrow_, address spendPermissionManager_) TokenCollector(paymentEscrow_) {
        spendPermissionManager = SpendPermissionManager(payable(spendPermissionManager_));
    }

    /// @inheritdoc TokenCollector
    /// @dev Supports Spend Permission approval signatures and MagicSpend WithdrawRequests (both optional)
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) external override onlyPaymentEscrow {
        address treasury = paymentEscrow.getOperatorTreasury(paymentInfo.operator);
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentInfo.payer,
            spender: address(this),
            token: paymentInfo.token,
            allowance: uint160(paymentInfo.maxAmount),
            period: type(uint48).max,
            start: 0,
            end: paymentInfo.preApprovalExpiry,
            salt: uint256(paymentInfoHash),
            extraData: hex""
        });

        (bytes memory signature, bytes memory encodedWithdrawRequest) = abi.decode(collectorData, (bytes, bytes));

        // Approve spend permission with signature if provided
        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, signature);
            if (!approved) revert SpendPermissionApprovalFailed();
        }

        // Transfer tokens into collector, potentially using account withdraw request if provided
        if (encodedWithdrawRequest.length == 0) {
            spendPermissionManager.spend(permission, uint160(amount));
        } else {
            MagicSpend.WithdrawRequest memory withdrawRequest =
                abi.decode(encodedWithdrawRequest, (MagicSpend.WithdrawRequest));
            spendPermissionManager.spendWithWithdraw(permission, uint160(amount), withdrawRequest);
        }

        // Transfer tokens from collector to escrow
        SafeTransferLib.safeTransfer(paymentInfo.token, treasury, amount);
    }
}
