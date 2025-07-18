// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

/// @title PreApprovalPaymentCollector
///
/// @notice Collect payments using pre-approval calls and ERC-20 allowances
///
/// @author Coinbase (https://github.com/base/commerce-payments)
contract PreApprovalPaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Payment was pre-approved by payer
    event PaymentPreApproved(bytes32 indexed paymentInfoHash);

    /// @notice Payment not pre-approved by payer
    error PaymentNotPreApproved(bytes32 paymentInfoHash);

    /// @notice Payment already collected
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);

    /// @notice Payment already pre-approved by payer
    error PaymentAlreadyPreApproved(bytes32 paymentInfoHash);

    /// @notice Track if a payment has been pre-approved
    mapping(bytes32 paymentInfoHash => bool approved) public isPreApproved;

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    constructor(address authCaptureEscrow_) TokenCollector(authCaptureEscrow_) {}

    /// @notice Registers payer's token approval for a specific payment
    ///
    /// @dev Must be called by the payer specified in the payment info
    ///
    /// @param paymentInfo PaymentInfo struct
    function preApprove(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check sender is payer
        if (msg.sender != paymentInfo.payer) revert AuthCaptureEscrow.InvalidSender(msg.sender, paymentInfo.payer);

        // Check pre-approval expiry has not passed
        if (block.timestamp >= paymentInfo.preApprovalExpiry) {
            revert AuthCaptureEscrow.AfterPreApprovalExpiry(uint48(block.timestamp), paymentInfo.preApprovalExpiry);
        }

        // Check has not already pre-approved
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        if (isPreApproved[paymentInfoHash]) revert PaymentAlreadyPreApproved(paymentInfoHash);

        // Check has not already collected
        (bool hasCollectedPayment,,) = authCaptureEscrow.paymentState(paymentInfoHash);
        if (hasCollectedPayment) revert PaymentAlreadyCollected(paymentInfoHash);

        // Set payment as pre-approved
        isPreApproved[paymentInfoHash] = true;
        emit PaymentPreApproved(paymentInfoHash);
    }

    /// @inheritdoc TokenCollector
    ///
    /// @dev Requires pre-approval for a specific payment and an ERC-20 allowance to this collector
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata
    ) internal override {
        // Check payment pre-approved
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        // Skip resetting pre-approval to save gas as the `AuthCaptureEscrow` enforces unique, single-lifecycle payments
        if (!isPreApproved[paymentInfoHash]) revert PaymentNotPreApproved(paymentInfoHash);
        // Transfer tokens from payer directly to token store
        SafeERC20.safeTransferFrom(IERC20(paymentInfo.token), paymentInfo.payer, tokenStore, amount);
    }
}
