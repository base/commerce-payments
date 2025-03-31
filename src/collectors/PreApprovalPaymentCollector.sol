// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract PreApprovalPaymentCollector is TokenCollector {
    event PaymentApproved(bytes32 indexed paymentDetailsHash);

    error PaymentAlreadyPreApproved(bytes32 paymentDetailsHash);
    error PaymentNotApproved(bytes32 paymentDetailsHash);
    error PaymentAlreadyCollected(bytes32 paymentDetailsHash);

    mapping(bytes32 => bool) public isPreApproved;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    function getCollectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
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
        isPreApproved[paymentDetailsHash] = true;
        emit PaymentApproved(paymentDetailsHash);
    }

    /// @inheritdoc TokenCollector
    function collectTokens(PaymentEscrow.PaymentDetails calldata paymentDetails, uint256 amount, bytes calldata)
        external
        override
        onlyPaymentEscrow
    {
        // check payment pre-approved
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        if (!isPreApproved[paymentDetailsHash]) revert PaymentNotApproved(paymentDetailsHash);

        // transfer tokens from payer to escrow
        SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.payer, address(paymentEscrow), amount);
    }
}
