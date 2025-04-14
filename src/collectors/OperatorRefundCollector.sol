// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

/// @title OperatorRefundCollector
/// @notice Collect refunds using ERC-20 allowances from operators
/// @author Coinbase
contract OperatorRefundCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Refund;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    /// @dev Requires previous ERC-20 allowance set by operator on this token collector
    /// @dev Only operator can initate token collection so authentication is inherited from Escrow
    function collectTokens(PaymentEscrow.PaymentInfo calldata paymentInfo, uint256 amount, bytes calldata)
        external
        override
        onlyPaymentEscrow
    {
        address operator = paymentInfo.operator;
        address tokenStore = paymentEscrow.getTokenStore(operator);

        // Transfer tokens from operator directly to token store
        SafeTransferLib.safeTransferFrom(paymentInfo.token, operator, tokenStore, amount);
    }
}
