// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title SpendPermissionPaymentCollector
/// @notice Collect payments using Spend Permissions
/// @author Coinbase
contract SpendPermissionPaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice SpendPermissionManager singleton
    SpendPermissionManager public immutable spendPermissionManager;

    /// @notice Spend permission approval failed
    error SpendPermissionApprovalFailed();

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    /// @param spendPermissionManager_ SpendPermissionManager singleton
    constructor(address paymentEscrow_, address spendPermissionManager_) TokenCollector(paymentEscrow_) {
        spendPermissionManager = SpendPermissionManager(payable(spendPermissionManager_));
    }

    /// @inheritdoc TokenCollector
    /// @dev Supports Spend Permission approval signatures and MagicSpend WithdrawRequests (both optional)
    function _collectTokens(
        PaymentEscrow.PaymentInfo calldata paymentInfo,
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
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);
        SafeERC20.safeTransfer(IERC20(token), tokenStore, amount);
    }
}
