// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";

import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract RefundTest is AuthCaptureEscrowBase {
    function test_reverts_whenValueIsZero() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(AuthCaptureEscrow.ZeroAmount.selector);
        authCaptureEscrow.refund(paymentInfo, 0, address(0), hex"");
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1});

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.AmountOverflow.selector, overflowValue, type(uint120).max)
        );
        authCaptureEscrow.refund(paymentInfo, overflowValue, address(0), hex"");
    }

    function test_reverts_whenSenderNotOperator(uint120 authorizedAmount, uint120 refundAmount) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.InvalidSender.selector, randomAddress, paymentInfo.operator)
        );
        authCaptureEscrow.refund(paymentInfo, refundAmount, address(0), hex"");
    }

    function test_reverts_afterRefundExpiry(uint120 authorizedAmount, uint120 refundAmount, uint48 refundExpiry)
        public
    {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0);
        vm.assume(refundExpiry < uint48(block.timestamp));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.refundExpiry = refundExpiry;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.AfterRefundExpiry.selector, uint48(block.timestamp), refundExpiry)
        );
        authCaptureEscrow.refund(paymentInfo, refundAmount, address(0), hex"");
    }

    function test_reverts_whenRefundExceedsCaptured(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= payerBalance); // Changed from > 0 to > 1
        uint256 captureAmount = authorizedAmount / 2; // Charge only half
        uint256 refundAmount = authorizedAmount; // Try to refund full amount

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm and capture partial amount
        vm.startPrank(operator);
        authCaptureEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);
        authCaptureEscrow.capture(paymentInfo, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(authCaptureEscrow), refundAmount);

        // Try to refund more than charged
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.RefundExceedsCapture.selector, refundAmount, captureAmount)
        );
        authCaptureEscrow.refund(paymentInfo, refundAmount, address(0), hex"");
    }

    function test_succeeds_whenCalledByOperator(uint120 authorizedAmount, uint120 refundAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        authCaptureEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);
        authCaptureEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();

        // Fund the operator for refund
        mockERC3009Token.mint(operator, refundAmount);

        // Approve operator refund collector to pull refund amount
        vm.prank(operator);
        mockERC3009Token.approve(address(operatorRefundCollector), refundAmount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 operatorBalanceBefore = mockERC3009Token.balanceOf(operator);

        // Execute refund
        vm.prank(operator);
        authCaptureEscrow.refund(paymentInfo, refundAmount, address(operatorRefundCollector), hex"");

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(operator), operatorBalanceBefore - refundAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + refundAmount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 refundAmount) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm and capture the payment
        vm.startPrank(operator);
        authCaptureEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);
        authCaptureEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(operatorRefundCollector), refundAmount);

        // Record expected event
        vm.expectEmit(true, true, false, true);
        emit AuthCaptureEscrow.PaymentRefunded(paymentInfoHash, refundAmount, address(operatorRefundCollector));

        // Execute refund
        vm.prank(operator);
        authCaptureEscrow.refund(paymentInfo, refundAmount, address(operatorRefundCollector), hex"");
    }
}
