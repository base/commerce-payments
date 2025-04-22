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

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    constructor(address paymentEscrow_) {
        paymentEscrow = PaymentEscrow(paymentEscrow_);
    }

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    /// @param paymentInfo Payment info struct
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function collectTokens(PaymentEscrow.PaymentInfo calldata paymentInfo, uint256 amount, bytes calldata collectorData)
        external
    {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _collectTokens(paymentInfo, amount, collectorData);
    }

    /// @notice Get the type of token collector
    /// @return CollectorType Type of token collector
    function collectorType() external view virtual returns (CollectorType);

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    /// @param paymentInfo Payment info struct
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function _collectTokens(
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        bytes calldata collectorData
    ) internal virtual;

    /// @notice Get hash for PaymentInfo with null payer address
    /// @dev Proactively setting payer back to original value covers accidental bugs of memory location being used elsewhere
    /// @param paymentInfo PaymentInfo struct with non-null payer address
    /// @return hash Hash of PaymentInfo with payer replaced with zero address
    function _getHashPayerAgnostic(PaymentEscrow.PaymentInfo memory paymentInfo) internal view returns (bytes32) {
        address payer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 hashPayerAgnostic = paymentEscrow.getHash(paymentInfo);
        paymentInfo.payer = payer;
        return hashPayerAgnostic;
    }
}
