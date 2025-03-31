// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {TokenCollector} from "../../src/collectors/TokenCollector.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Mock token collector that does not transfer sufficient tokens
contract ERC20UnsafeTransferTokenCollector is TokenCollector {
    event PaymentApproved(bytes32 indexed paymentDetailsHash);

    error PaymentAlreadyPreApproved(bytes32 paymentDetailsHash);
    error PaymentNotApproved(bytes32 paymentDetailsHash);
    error PaymentAlreadyCollected(bytes32 paymentDetailsHash);
    error InvalidSender(address sender, address expected);

    mapping(bytes32 => bool) public isPreApproved;

    constructor(address _paymentEscrow) TokenCollector(_paymentEscrow) {}

    /// @inheritdoc TokenCollector
    function collectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment details
    /// @param paymentDetails PaymentDetails struct
    function preApprove(PaymentEscrow.PaymentDetails calldata paymentDetails) external {
        // check sender is buyer
        if (msg.sender != paymentDetails.payer) revert InvalidSender(msg.sender, paymentDetails.payer);

        // check status is not authorized or already pre-approved
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        if (paymentEscrow.hasCollected(paymentDetailsHash)) revert PaymentAlreadyCollected(paymentDetailsHash);
        if (isPreApproved[paymentDetailsHash]) revert PaymentAlreadyPreApproved(paymentDetailsHash);
        isPreApproved[paymentDetailsHash] = true;
        emit PaymentApproved(paymentDetailsHash);
    }

    function collectTokens(
        bytes32 paymentDetailsHash,
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        uint256,
        bytes calldata
    ) external override onlyPaymentEscrow {
        if (!isPreApproved[paymentDetailsHash]) {
            revert PaymentNotApproved(paymentDetailsHash);
        }
        // transfer too few token to escrow
        IERC20(paymentDetails.token).transferFrom(
            paymentDetails.payer, address(paymentEscrow), paymentDetails.maxAmount - 1
        );
    }
}
