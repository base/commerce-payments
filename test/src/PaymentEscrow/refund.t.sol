// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RefundTest is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.refund(0, paymentDetails);
    }

    function test_reverts_whenValueOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1});

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.refund(overflowValue, paymentDetails);
    }

    function test_reverts_whenSenderNotOperatorOrCaptureAddress(uint120 authorizedAmount, uint120 refundAmount)
        public
    {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, randomAddress));
        paymentEscrow.refund(refundAmount, paymentDetails);
    }

    function test_reverts_whenRefundExceedsCaptured(uint120 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= buyerBalance); // Changed from > 0 to > 1
        uint256 chargeAmount = authorizedAmount / 2; // Charge only half
        uint256 refundAmount = authorizedAmount; // Try to refund full amount

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm and capture partial amount
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(chargeAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        // Try to refund more than charged
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, refundAmount, chargeAmount));
        paymentEscrow.refund(refundAmount, paymentDetails);
    }

    function test_succeeds_whenCalledByOperator(uint120 authorizedAmount, uint120 refundAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
        vm.stopPrank();

        // Fund the operator for refund
        mockERC3009Token.mint(operator, refundAmount);

        // Approve escrow to pull refund amount
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
    }

    function test_succeeds_whenCalledByCaptureAddress(uint120 authorizedAmount, uint120 refundAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
        vm.stopPrank();

        // Fund the captureAddress for refund
        mockERC3009Token.mint(captureAddress, refundAmount);

        // Approve escrow to pull refund amount
        vm.prank(captureAddress);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 captureAddressBalanceBefore = mockERC3009Token.balanceOf(captureAddress);

        // Execute refund
        vm.prank(captureAddress);
        paymentEscrow.refund(refundAmount, paymentDetails);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressBalanceBefore - refundAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore + refundAmount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 refundAmount) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        mockERC3009Token.mint(buyerEOA, authorizedAmount);
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        // Record expected event
        vm.expectEmit(true, true, false, true);
        emit PaymentEscrow.PaymentRefunded(paymentDetailsHash, refundAmount, operator);

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(refundAmount, paymentDetails);
    }
}
