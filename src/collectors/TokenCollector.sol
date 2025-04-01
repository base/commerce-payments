// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title TokenCollector
/// @notice Abstract contract for shared token collector utilities
/// @author Coinbase
abstract contract TokenCollector {
    /// @notice Type differentiation between payment and refund collection flows
    enum CollectorType {
        Payment,
        Refund
    }

    /// @notice PaymentEscrow singleton
    PaymentEscrow public immutable paymentEscrow;

    /// @notice Call sender is not PaymentEscrow
    error OnlyPaymentEscrow();

    constructor(address paymentEscrow_) {
        paymentEscrow = PaymentEscrow(paymentEscrow_);
    }

    /// @notice Enforce only PaymentEscrow can call
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
    /// @return CollectorType Type of token collector
    function collectorType() external view virtual returns (CollectorType);
}
