// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../PaymentEscrow.sol";

abstract contract IPullTokensHook {
    error OnlyPaymentEscrow();

    PaymentEscrow public immutable paymentEscrow;

    constructor(address _paymentEscrow) {
        paymentEscrow = PaymentEscrow(_paymentEscrow);
    }

    modifier onlyPaymentEscrow() {
        if (msg.sender != address(paymentEscrow)) revert OnlyPaymentEscrow();
        _;
    }

    /// @notice Pull tokens from payer to escrow using hook-specific authorization logic
    /// @param paymentDetails Payment details for use as nonce/salt
    /// @param paymentDetailsHash Hash of payment details for use as nonce/salt
    /// @param value Amount of tokens to transfer
    /// @param signature Authorization signature (format depends on hook implementation)
    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata signature,
        bytes calldata hookData
    ) external virtual;
}
