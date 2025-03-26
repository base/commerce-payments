// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract CaptureTest is PaymentEscrowBase {
    function test_reverts_whenNotOperator(uint120 authorizedAmount, address sender) public {
        vm.assume(authorizedAmount > 0);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        vm.assume(sender != paymentDetails.operator);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(paymentDetails.operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, sender));
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.capture(0, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenValueOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: 1});

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.capture(overflowValue, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenAfterAuthorizationExpiry(
        uint256 authorizedAmount,
        uint256 captureAmount,
        uint48 authorizationExpiry
    ) public {
        vm.assume(authorizationExpiry > 1 && authorizationExpiry < type(uint40).max);
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(captureAmount > 0 && captureAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        paymentDetails.authorizationExpiry = authorizationExpiry;
        paymentDetails.preApprovalExpiry = authorizationExpiry;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.warp(paymentDetails.preApprovalExpiry - 1);
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        vm.warp(authorizationExpiry + 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationExpiry.selector, block.timestamp, authorizationExpiry
            )
        );
        paymentEscrow.capture(captureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenInsufficientAuthorization(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        uint256 captureAmount = authorizedAmount + 1; // Try to capture more than authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

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
        paymentEscrow.capture(captureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_receiverSender(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // Then capture the full amount
        vm.prank(paymentDetails.receiver);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, paymentDetails.receiver));
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_succeeds_withFullAmount(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        uint256 feeAmount = authorizedAmount * FEE_BPS / 10_000;
        uint256 receiverExpectedBalance = authorizedAmount - feeAmount;

        // Then capture the full amount
        vm.prank(operator);
        paymentEscrow.capture(authorizedAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_succeeds_withPartialAmount(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= payerBalance);
        uint256 captureAmount = authorizedAmount / 2;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        uint256 feeAmount = captureAmount * FEE_BPS / 10_000;
        uint256 receiverExpectedBalance = captureAmount - feeAmount;

        // Then capture partial amount
        vm.prank(operator);
        paymentEscrow.capture(captureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);

        // Verify balances and state
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), authorizedAmount - captureAmount);
    }

    function test_succeeds_withMultipleCaptures(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 2 && authorizedAmount <= payerBalance);
        uint256 firstCaptureAmount = authorizedAmount / 2;
        uint256 secondCaptureAmount = authorizedAmount - firstCaptureAmount;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // First capture
        vm.prank(operator);
        paymentEscrow.capture(firstCaptureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);

        // Second capture
        vm.prank(operator);
        paymentEscrow.capture(
            secondCaptureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient
        );

        // Calculate fees for each capture separately to match contract behavior
        uint256 firstFeesAmount = firstCaptureAmount * FEE_BPS / 10_000;
        uint256 secondFeesAmount = secondCaptureAmount * FEE_BPS / 10_000;
        uint256 totalFeeAmount = firstFeesAmount + secondFeesAmount;

        // Calculate expected capture address balance by subtracting fees from each capture
        uint256 receiverExpectedBalance =
            (firstCaptureAmount - firstFeesAmount) + (secondCaptureAmount - secondFeesAmount);

        // Verify final state
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), totalFeeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 captureAmount = 60e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentCaptured(paymentDetailsHash, captureAmount, operator);

        // Execute capture
        vm.prank(operator);
        paymentEscrow.capture(captureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenFeeBpsBelowMin(
        uint120 authorizedAmount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps
    ) public {
        // Assume reasonable bounds for fees
        vm.assume(authorizedAmount > 0);
        vm.assume(minFeeBps > 0 && minFeeBps <= 5000); // Max 50%
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps <= 5000);
        vm.assume(captureFeeBps < minFeeBps); // Must be below min to trigger revert

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        paymentDetails.minFeeBps = minFeeBps;
        paymentDetails.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(paymentDetails.operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.capture(authorizedAmount, paymentDetails, captureFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_whenFeeBpsAboveMax(
        uint120 authorizedAmount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps
    ) public {
        // Assume reasonable bounds for fees
        vm.assume(authorizedAmount > 0);
        vm.assume(minFeeBps <= 5000); // Max 50%
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps <= 5000);
        vm.assume(captureFeeBps > maxFeeBps); // Must be above max to trigger revert
        vm.assume(captureFeeBps <= 10_000); // But still within uint16 reasonable bounds

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        paymentDetails.minFeeBps = minFeeBps;
        paymentDetails.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(paymentDetails.operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.capture(authorizedAmount, paymentDetails, captureFeeBps, paymentDetails.feeRecipient);
    }

    function test_succeeds_withOperatorSetFeeRecipient(
        uint120 authorizedAmount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps
    ) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(minFeeBps > 0);
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps < 10000);
        vm.assume(captureFeeBps >= minFeeBps && captureFeeBps <= maxFeeBps);

        mockERC3009Token.mint(payerEOA, authorizedAmount);
        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: authorizedAmount,
            token: address(mockERC3009Token),
            hook: PullTokensHook.ERC3009
        });
        paymentDetails.feeRecipient = address(0);
        paymentDetails.minFeeBps = minFeeBps;
        paymentDetails.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(paymentDetails.operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);

        address newFeeRecipient = address(0xdead);

        vm.prank(operator);
        paymentEscrow.capture(authorizedAmount, paymentDetails, captureFeeBps, newFeeRecipient);

        uint256 feeAmount = (uint256(authorizedAmount) * uint256(captureFeeBps)) / 10_000;
        assertEq(mockERC3009Token.balanceOf(newFeeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(receiver), authorizedAmount - feeAmount);
    }
}
