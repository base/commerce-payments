// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {TokenCollector} from "./TokenCollector.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract OperatorRefundCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Refund;

    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    /// @dev Requires previous ERC-20 allowance set by operator on this token collector
    /// @dev Only operator can initate token collection so authentication is inherited from Escrow
    function collectTokens(
        bytes32,
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata
    ) external override onlyPaymentEscrow {
        // transfer tokens from operator to escrow
        SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.operator, address(paymentEscrow), amount);
    }
}
