// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract CaptureTest is PaymentEscrowBase {
    function test_reverts_whenNotOperator(address sender) public {
        uint256 authorizedAmount = 100e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.assume(sender != paymentDetails.operator);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, sender));
        paymentEscrow.capture(authorizedAmount, paymentDetails);
    }

    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.capture(0, paymentDetails);
    }

    function test_reverts_whenValueOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1});

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.capture(overflowValue, paymentDetails);
    }

    function test_reverts_whenAfterCaptureDeadline(
        uint256 authorizedAmount,
        uint256 captureAmount,
        uint48 captureDeadline
    ) public {
        vm.assume(captureDeadline > 1 && captureDeadline < type(uint40).max);
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(captureAmount > 0 && captureAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.authorizeDeadline = captureDeadline;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.warp(paymentDetails.authorizeDeadline - 1);
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        vm.warp(captureDeadline + 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.AfterCaptureDeadline.selector, block.timestamp, captureDeadline)
        );
        paymentEscrow.capture(captureAmount, paymentDetails);
    }

    function test_reverts_whenInsufficientAuthorization(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        uint256 captureAmount = authorizedAmount + 1; // Try to capture more than authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // Try to capture more than authorized
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InsufficientAuthorization.selector, paymentDetailsHash, authorizedAmount, captureAmount
            )
        );
        paymentEscrow.capture(captureAmount, paymentDetails);
    }

    function test_succeeds_withFullAmount(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        uint256 feeAmount = authorizedAmount * FEE_BPS / 10_000;
        uint256 captureAddressExpectedBalance = authorizedAmount - feeAmount;

        // Then capture the full amount
        vm.prank(operator);
        paymentEscrow.capture(authorizedAmount, paymentDetails);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_succeeds_withPartialAmount(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= buyerBalance);
        uint256 captureAmount = authorizedAmount / 2;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        uint256 feeAmount = captureAmount * FEE_BPS / 10_000;
        uint256 captureAddressExpectedBalance = captureAmount - feeAmount;

        // Then capture partial amount
        vm.prank(operator);
        paymentEscrow.capture(captureAmount, paymentDetails);

        // Verify balances and state
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), authorizedAmount - captureAmount);
    }

    function test_succeeds_withMultipleCaptures(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 2 && authorizedAmount <= buyerBalance);
        uint256 firstCaptureAmount = authorizedAmount / 2;
        uint256 secondCaptureAmount = authorizedAmount - firstCaptureAmount;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // First capture
        vm.prank(operator);
        paymentEscrow.capture(firstCaptureAmount, paymentDetails);

        // Second capture
        vm.prank(operator);
        paymentEscrow.capture(secondCaptureAmount, paymentDetails);

        // Calculate fees for each capture separately to match contract behavior
        uint256 firstFeesAmount = firstCaptureAmount * FEE_BPS / 10_000;
        uint256 secondFeesAmount = secondCaptureAmount * FEE_BPS / 10_000;
        uint256 totalFeeAmount = firstFeesAmount + secondFeesAmount;

        // Calculate expected capture address balance by subtracting fees from each capture
        uint256 captureAddressExpectedBalance =
            (firstCaptureAmount - firstFeesAmount) + (secondCaptureAmount - secondFeesAmount);

        // Verify final state
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), totalFeeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_succeeds_captureAddressSender(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        uint256 feeAmount = authorizedAmount * FEE_BPS / 10_000;
        uint256 captureAddressExpectedBalance = authorizedAmount - feeAmount;

        // Then capture the full amount
        vm.prank(paymentDetails.captureAddress);
        paymentEscrow.capture(authorizedAmount, paymentDetails);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 captureAmount = 60e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentCaptured(paymentDetailsHash, captureAmount, operator);

        // Execute capture
        vm.prank(operator);
        paymentEscrow.capture(captureAmount, paymentDetails);
    }
}
