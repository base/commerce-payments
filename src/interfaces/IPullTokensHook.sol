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
    /// @param pullTokensData Data required to pull tokens from payer to escrow
    function pullTokens(PaymentEscrow.PullTokensData memory pullTokensData) external virtual;
}
