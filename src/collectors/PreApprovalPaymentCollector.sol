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
    event PaymentPreApproved(bytes32 indexed paymentDetailsHash);

    /// @notice Payment not pre-approved by buyer
    error PaymentNotPreApproved(bytes32 paymentDetailsHash);

    /// @notice Payment already collected
    error PaymentAlreadyCollected(bytes32 paymentDetailsHash);

    /// @notice Payment already pre-approved by buyer
    error PaymentAlreadyPreApproved(bytes32 paymentDetailsHash);

    /// @notice Track if a payment has been pre-approved
    mapping(bytes32 paymentDetailsHash => bool approved) public isPreApproved;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    /// @dev Requires pre-approval for a specific payment and an ERC-20 allowance to this collector
    function collectTokens(
        bytes32 paymentDetailsHash,
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata
    ) external override onlyPaymentEscrow {
        // check payment pre-approved
        if (!isPreApproved[paymentDetailsHash]) revert PaymentNotPreApproved(paymentDetailsHash);

        // transfer tokens from payer to escrow
        SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.payer, address(paymentEscrow), amount);
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment details
    /// @param paymentDetails PaymentDetails struct
    function preApprove(PaymentEscrow.PaymentDetails calldata paymentDetails) external {
        // check sender is buyer
        if (msg.sender != paymentDetails.payer) revert PaymentEscrow.InvalidSender(msg.sender, paymentDetails.payer);

        // check status is not authorized or already pre-approved
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        if (paymentEscrow.hasCollected(paymentDetailsHash)) revert PaymentAlreadyCollected(paymentDetailsHash);
        if (isPreApproved[paymentDetailsHash]) revert PaymentAlreadyPreApproved(paymentDetailsHash);

        // set payment as pre-approved
        isPreApproved[paymentDetailsHash] = true;
        emit PaymentPreApproved(paymentDetailsHash);
    }
}
