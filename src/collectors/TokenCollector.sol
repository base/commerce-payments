// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../PaymentEscrow.sol";

abstract contract TokenCollector {
    PaymentEscrow public immutable paymentEscrow;

    enum CollectorType {
        Payment,
        Refund
    }

    error OnlyPaymentEscrow();

    constructor(address paymentEscrow_) {
        paymentEscrow = PaymentEscrow(paymentEscrow_);
    }

    modifier onlyPaymentEscrow() {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _;
    }

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    /// @param paymentDetailsHash Hash of payment details
    /// @param paymentDetails Payment details struct
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function collectTokens(
        bytes32 paymentDetailsHash,
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external virtual;

    /// @notice Get the type of token collector
    /// @return collectorType Type of token collector
    function collectorType() external view virtual returns (CollectorType);
}
