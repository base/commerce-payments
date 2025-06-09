// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

/// @title TokenCollector
///
/// @notice Abstract contract for shared token collector utilities
///
/// @author Coinbase (https://github.com/base/commerce-payments)
abstract contract TokenCollector {
    /// @notice Type differentiation between payment and refund collection flows
    enum CollectorType {
        Payment,
        Refund
    }

    /// @notice AuthCaptureEscrow singleton
    AuthCaptureEscrow public immutable authCaptureEscrow;

    /// @notice Call sender is not AuthCaptureEscrow
    error OnlyAuthCaptureEscrow();

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    constructor(address authCaptureEscrow_) {
        authCaptureEscrow = AuthCaptureEscrow(authCaptureEscrow_);
    }

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    ///
    /// @param paymentInfo Payment info struct
    /// @param tokenStore Address to collect tokens into
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) external {
        if (msg.sender != address(authCaptureEscrow)) revert OnlyAuthCaptureEscrow();
        _collectTokens(paymentInfo, tokenStore, amount, collectorData);
    }

    /// @notice Get the type of token collector
    ///
    /// @return CollectorType Type of token collector
    function collectorType() external view virtual returns (CollectorType);

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    ///
    /// @param paymentInfo Payment info struct
    /// @param tokenStore Address to collect tokens into
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal virtual;

    /// @notice Get hash for PaymentInfo with null payer address
    ///
    /// @param paymentInfo PaymentInfo struct with non-null payer address
    ///
    /// @return hash Hash of PaymentInfo with payer replaced with zero address
    function _getHashPayerAgnostic(AuthCaptureEscrow.PaymentInfo memory paymentInfo) internal view returns (bytes32) {
        address payer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 hashPayerAgnostic = authCaptureEscrow.getHash(paymentInfo);
        // Proactively setting payer back to original value covers accidental bugs if memory location is then used elsewhere
        paymentInfo.payer = payer;
        return hashPayerAgnostic;
    }
}
