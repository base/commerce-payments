// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

/// @title SpendPermissionPaymentCollector
///
/// @notice Collect payments using Spend Permissions
///
/// @author Coinbase (https://github.com/base/commerce-payments)
contract SpendPermissionPaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice SpendPermissionManager singleton
    SpendPermissionManager public immutable spendPermissionManager;

    /// @notice Spend permission approval failed
    error SpendPermissionApprovalFailed();

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    /// @param spendPermissionManager_ SpendPermissionManager singleton
    constructor(address authCaptureEscrow_, address spendPermissionManager_) TokenCollector(authCaptureEscrow_) {
        spendPermissionManager = SpendPermissionManager(payable(spendPermissionManager_));
    }

    /// @inheritdoc TokenCollector
    ///
    /// @dev Supports Spend Permission approval signatures and MagicSpend WithdrawRequests (both optional)
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        address token = paymentInfo.token;
        SpendPermissionManager.SpendPermission memory permission = SpendPermissionManager.SpendPermission({
            account: paymentInfo.payer,
            spender: address(this),
            token: token,
            allowance: uint160(paymentInfo.maxAmount),
            period: type(uint48).max,
            start: 0,
            end: paymentInfo.preApprovalExpiry,
            salt: uint256(_getHashPayerAgnostic(paymentInfo)),
            extraData: hex""
        });

        (bytes memory signature, bytes memory encodedWithdrawRequest) = abi.decode(collectorData, (bytes, bytes));

        // Approve spend permission with signature if provided
        if (signature.length > 0) {
            bool approved = spendPermissionManager.approveWithSignature(permission, signature);
            if (!approved) revert SpendPermissionApprovalFailed();
        }

        // Transfer tokens into collector, first using a MagicSpend WithdrawRequest if provided
        if (encodedWithdrawRequest.length == 0) {
            spendPermissionManager.spend(permission, uint160(amount));
        } else {
            MagicSpend.WithdrawRequest memory withdrawRequest =
                abi.decode(encodedWithdrawRequest, (MagicSpend.WithdrawRequest));
            spendPermissionManager.spendWithWithdraw(permission, uint160(amount), withdrawRequest);
        }

        // Transfer tokens from collector to token store
        SafeERC20.safeTransfer(IERC20(token), tokenStore, amount);
    }
}
