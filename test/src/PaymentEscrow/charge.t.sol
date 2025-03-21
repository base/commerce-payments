// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract ChargeTest is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1}); // Any non-zero value

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.charge(0, paymentDetails, signature);
    }

    function test_reverts_whenValueOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1});

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.charge(overflowValue, paymentDetails, signature);
    }

    function test_reverts_whenCallerIsNotOperatorOrCaptureAddress(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != captureAddress);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.charge(amount, paymentDetails, signature);
    }

    function test_reverts_whenValueExceedsAuthorized(uint120 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        uint256 chargeAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueLimitExceeded.selector, chargeAmount));
        paymentEscrow.charge(chargeAmount, paymentDetails, "");
    }

    function test_reverts_whenAfterAuthorizationDeadline(uint120 amount, uint48 captureDeadline) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);
        vm.assume(captureDeadline > 0 && captureDeadline < type(uint48).max);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(buyerEOA, amount);
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.authorizeDeadline = captureDeadline;

        // Set time to after the capture deadline
        vm.warp(captureDeadline + 1);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationDeadline.selector,
                uint48(block.timestamp),
                paymentDetails.authorizeDeadline
            )
        );
        paymentEscrow.charge(amount, paymentDetails, signature);
    }

    function test_reverts_whenAuthorizationDeadlineAfterCaptureDeadline(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Set authorize deadline after capture deadline
        uint48 captureDeadline = uint48(block.timestamp + 1 days);
        uint48 authorizeDeadline = captureDeadline + 1; // One second later
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.authorizeDeadline = authorizeDeadline;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidDeadlines.selector, authorizeDeadline, captureDeadline)
        );
        paymentEscrow.charge(amount, paymentDetails, signature);
    }

    function test_reverts_whenAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First authorization
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Try to charge now with same payment details
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(operator);
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyAuthorized.selector, paymentDetailsHash));
        paymentEscrow.charge(amount, paymentDetails, signature);
    }

    function test_reverts_ifSignatureIsEmptyAndTokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Give buyer tokens and approve escrow
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to charge without pre-approval in Escrow contract
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.PaymentNotApproved.selector, keccak256(abi.encode(paymentDetails)))
        );
        paymentEscrow.charge(amount, paymentDetails, "");
    }

    function test_reverts_ifSignatureIsEmptyAndTokenIsPreApprovedButFundsAreNotTransferred(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Pre-approve in escrow
        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Give buyer tokens but DON'T approve escrow
        mockERC3009Token.mint(buyerEOA, amount);

        // Try to charge - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.charge(amount, paymentDetails, "");
    }

    function test_succeeds_ifSignatureIsEmptyAndTokenIsPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Pre-approve in escrow
        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Give buyer tokens and approve escrow
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 captureAddressBalanceBefore = mockERC3009Token.balanceOf(captureAddress);
        uint256 feeRecipientBalanceBefore = mockERC3009Token.balanceOf(feeRecipient);

        // Charge with empty signature
        vm.prank(operator);
        paymentEscrow.charge(amount, paymentDetails, "");

        // Verify balances including fee distribution
        uint256 feeAmount = uint256(amount) * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressBalanceBefore + (amount - feeAmount));
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeRecipientBalanceBefore + feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }

    function test_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(amount > 0 && amount <= buyerBalance);
        mockERC3009Token.mint(buyerEOA, amount);
        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(buyerEOA, amount);
        vm.warp(paymentDetails.captureDeadline - 1);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.charge(amount, paymentDetails, signature);

        uint256 feeAmount = amount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), amount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }

    function test_succeeds_whenValueLessThanAuthorized(uint120 authorizedAmount, uint120 chargeAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(chargeAmount > 0 && chargeAmount < authorizedAmount);

        mockERC3009Token.mint(buyerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.charge(chargeAmount, paymentDetails, signature);

        uint256 feeAmount = chargeAmount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), chargeAmount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - chargeAmount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 valueToCharge) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(valueToCharge > 0 && valueToCharge <= authorizedAmount);

        mockERC3009Token.mint(buyerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentCharged(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.buyer,
            paymentDetails.captureAddress,
            paymentDetails.token,
            valueToCharge
        );

        // Execute charge
        vm.prank(operator);
        paymentEscrow.charge(valueToCharge, paymentDetails, signature);
    }

    function test_allowsRefund(uint120 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 3 && authorizedAmount <= buyerBalance);

        uint256 chargeAmount = authorizedAmount / 2;
        uint256 refundAmount = chargeAmount / 2;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First charge the payment
        vm.prank(operator);
        paymentEscrow.charge(chargeAmount, paymentDetails, signature);

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 operatorBalanceBefore = mockERC3009Token.balanceOf(operator);

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(refundAmount, paymentDetails);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(operator), operatorBalanceBefore - refundAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore + refundAmount);

        // Try to refund more than remaining captured amount
        uint256 remainingCaptured = chargeAmount - refundAmount;
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, chargeAmount, remainingCaptured)
        );
        vm.prank(operator);
        paymentEscrow.refund(chargeAmount, paymentDetails);
    }
}
