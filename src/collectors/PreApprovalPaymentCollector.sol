// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title PreApprovalPaymentCollector
/// @notice Collect payments using pre-approval calls and ERC-20 allowances
/// @author Coinbase
contract PreApprovalPaymentCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Payment was pre-approved by buyer
    event PaymentPreApproved(bytes32 indexed paymentInfoHash);

    /// @notice Payment not pre-approved by buyer
    error PaymentNotPreApproved(bytes32 paymentInfoHash);

    /// @notice Payment already collected
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);

    /// @notice Payment already pre-approved by buyer
    error PaymentAlreadyPreApproved(bytes32 paymentInfoHash);

    /// @notice Track if a payment has been pre-approved
    mapping(bytes32 paymentInfoHash => bool approved) public isPreApproved;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    /// @dev Requires pre-approval for a specific payment and an ERC-20 allowance to this collector
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata
    ) external override onlyPaymentEscrow {
        _configureAllowance(paymentInfo.token);
        // Check payment pre-approved
        if (!isPreApproved[paymentInfoHash]) revert PaymentNotPreApproved(paymentInfoHash);

        // Transfer tokens from payer to this collector
        SafeTransferLib.safeTransferFrom(paymentInfo.token, paymentInfo.payer, address(this), amount);
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment info
    /// @param paymentInfo PaymentInfo struct
    function preApprove(PaymentEscrow.PaymentInfo calldata paymentInfo) external {
        // Check sender is buyer
        if (msg.sender != paymentInfo.payer) revert PaymentEscrow.InvalidSender(msg.sender, paymentInfo.payer);

        // Check status is not authorized or already pre-approved
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        (bool hasCollectedPayment,,) = paymentEscrow.paymentState(paymentInfoHash);
        if (hasCollectedPayment) {
            revert PaymentAlreadyCollected(paymentInfoHash);
        }
        if (isPreApproved[paymentInfoHash]) revert PaymentAlreadyPreApproved(paymentInfoHash);

        // Set payment as pre-approved
        isPreApproved[paymentInfoHash] = true;
        emit PaymentPreApproved(paymentInfoHash);
    }
}
