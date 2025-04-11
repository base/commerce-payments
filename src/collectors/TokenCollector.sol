// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

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
    /// @param paymentInfoHash Hash of payment info
    /// @param paymentInfo Payment info struct
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) external virtual;

    /// @notice Get the type of token collector
    /// @return CollectorType Type of token collector
    function collectorType() external view virtual returns (CollectorType);

    /// @notice Get hash for PaymentInfo with null payer address
    /// @dev Proactively setting payer back to original value covers accidental bugs of memory location being used elsewhere
    /// @param paymentInfo PaymentInfo struct with non-null payer address
    /// @return hash Hash of PaymentInfo with payer replaced with zero address
    function _getHashPayerAgnostic(PaymentEscrow.PaymentInfo memory paymentInfo) internal view returns (bytes32) {
        address payer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 hashPayerAgnostic = paymentEscrow.getHash(paymentInfo);
        return hashPayerAgnostic;
    }
}
