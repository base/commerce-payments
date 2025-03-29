// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RefundTest is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroAmount.selector);
        paymentEscrow.refund(paymentDetails, 0, address(0), hex"");
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1});

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.AmountOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.refund(paymentDetails, overflowValue, address(0), hex"");
    }

    function test_reverts_whenSenderNotOperator(uint120 authorizedAmount, uint120 refundAmount) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, randomAddress, paymentDetails.operator)
        );
        paymentEscrow.refund(paymentDetails, refundAmount, address(0), hex"");
    }

    function test_reverts_afterRefundExpiry(uint120 authorizedAmount, uint120 refundAmount, uint48 refundExpiry)
        public
    {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0);
        vm.assume(refundExpiry < uint48(block.timestamp));

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        paymentDetails.refundExpiry = refundExpiry;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.AfterRefundExpiry.selector, uint48(block.timestamp), refundExpiry)
        );
        paymentEscrow.refund(paymentDetails, refundAmount, address(0), hex"");
    }

    function test_reverts_whenRefundExceedsCaptured(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= payerBalance); // Changed from > 0 to > 1
        uint256 captureAmount = authorizedAmount / 2; // Charge only half
        uint256 refundAmount = authorizedAmount; // Try to refund full amount

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm and capture partial amount
        vm.startPrank(operator);
        paymentEscrow.authorize(paymentDetails, authorizedAmount, hooks[TokenCollector.ERC3009], signature);
        paymentEscrow.capture(paymentDetails, captureAmount, paymentDetails.minFeeBps, paymentDetails.feeReceiver);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        // Try to refund more than charged
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, refundAmount, captureAmount)
        );
        paymentEscrow.refund(paymentDetails, refundAmount, address(0), hex"");
    }

    function test_succeeds_whenCalledByOperator(uint120 authorizedAmount, uint120 refundAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(paymentDetails, authorizedAmount, hooks[TokenCollector.ERC3009], signature);
        paymentEscrow.capture(paymentDetails, authorizedAmount, paymentDetails.minFeeBps, paymentDetails.feeReceiver);
        vm.stopPrank();

        // Fund the operator for refund
        mockERC3009Token.mint(operator, refundAmount);

        // Approve escrow to pull refund amount
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 operatorBalanceBefore = mockERC3009Token.balanceOf(operator);

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(paymentDetails, refundAmount, address(0), hex"");

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(operator), operatorBalanceBefore - refundAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + refundAmount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 refundAmount) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(paymentDetails, authorizedAmount, hooks[TokenCollector.ERC3009], signature);
        paymentEscrow.capture(paymentDetails, authorizedAmount, paymentDetails.minFeeBps, paymentDetails.feeReceiver);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        // Record expected event
        vm.expectEmit(true, true, false, true);
        emit PaymentEscrow.PaymentRefunded(paymentDetailsHash, refundAmount, address(0));

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(paymentDetails, refundAmount, address(0), hex"");
    }
}
