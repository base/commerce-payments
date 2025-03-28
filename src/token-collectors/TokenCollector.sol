// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../PaymentEscrow.sol";

abstract contract TokenCollector {
    PaymentEscrow public immutable paymentEscrow;

    error OnlyPaymentEscrow();

    constructor(address _paymentEscrow) {
        paymentEscrow = PaymentEscrow(_paymentEscrow);
    }

    modifier onlyPaymentEscrow() {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _;
    }

    /// @notice Pull tokens from payer to escrow using token collector-specific authorization logic
    /// @param paymentDetails Payment details struct
    /// @param amount Amount of tokens to pull
    /// @param collectorData Data to pass to the token collector
    function collectTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256 amount,
        bytes calldata collectorData
    ) external virtual;
}
