// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";

/// @title OperatorRefundCollector
///
/// @notice Collect refunds using ERC-20 allowances from operators
///
/// @author Coinbase, Shopify
contract OperatorRefundCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Refund;

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    constructor(address authCaptureEscrow_) TokenCollector(authCaptureEscrow_) {}

    /// @inheritdoc TokenCollector
    ///
    /// @dev Transfers from operator directly to token store, requiring previous ERC-20 allowance set by operator on this token collector
    /// @dev Only operator can initate token collection so authentication is inherited from Escrow
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata
    ) internal override {
        SafeERC20.safeTransferFrom(IERC20(paymentInfo.token), paymentInfo.operator, tokenStore, amount);
    }
}
