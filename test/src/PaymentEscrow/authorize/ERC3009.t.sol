// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AuthorizeWithERC3009Test is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1}); // Any non-zero value

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.authorize(0, paymentDetails, signature);
    }

    function test_reverts_whenValueOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: 1});

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.authorize(overflowValue, paymentDetails, signature);
    }

    function test_reverts_whenCallerIsNotOperator(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.authorize(amount, paymentDetails, signature);
    }

    function test_reverts_whenValueExceedsAuthorized(uint120 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        uint256 confirmAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueLimitExceeded.selector, confirmAmount));
        paymentEscrow.authorize(confirmAmount, paymentDetails, signature);
    }

    function test_reverts_exactlyAtAuthorizationDeadline(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 authorizeDeadline = uint48(block.timestamp + 1 days);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        paymentDetails.authorizeDeadline = authorizeDeadline;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Set time to exactly at the authorize deadline
        vm.warp(authorizeDeadline);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationDeadline.selector, authorizeDeadline, authorizeDeadline
            )
        );
        paymentEscrow.authorize(amount, paymentDetails, signature);
    }

    function test_reverts_afterAuthorizationDeadline(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 authorizeDeadline = uint48(block.timestamp + 1 days);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        paymentDetails.authorizeDeadline = authorizeDeadline;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Set time to after the authorize deadline
        vm.warp(authorizeDeadline + 1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationDeadline.selector, authorizeDeadline + 1, authorizeDeadline
            )
        );
        paymentEscrow.authorize(amount, paymentDetails, signature);
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
        paymentEscrow.authorize(amount, paymentDetails, signature);
    }

    function test_reverts_whenFeeBpsTooHigh(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Set fee bps > 100%
        paymentDetails.feeBps = 10_001;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.FeeBpsOverflow.selector, 10_001));
        paymentEscrow.authorize(amount, paymentDetails, signature);
    }

    function test_reverts_whenFeeRecipientZeroButFeeBpsNonZero(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Set fee recipient to zero but keep non-zero fee bps
        paymentDetails.feeRecipient = address(0);
        paymentDetails.feeBps = 100; // 1%

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroFeeRecipient.selector);
        paymentEscrow.authorize(amount, paymentDetails, signature);
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

        // Try to authorize again with same payment details
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(operator);
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyAuthorized.selector, paymentDetailsHash));
        paymentEscrow.authorize(amount, paymentDetails, signature);
    }

    function test_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(buyerEOA, amount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), amount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }

    function test_succeeds_whenValueLessThanAuthorized(uint120 authorizedAmount, uint120 confirmAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(confirmAmount > 0 && confirmAmount < authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.authorize(confirmAmount, paymentDetails, signature);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), confirmAmount);
        assertEq(
            mockERC3009Token.balanceOf(buyerEOA),
            buyerBalanceBefore - authorizedAmount + (authorizedAmount - confirmAmount)
        );
    }

    function test_succeeds_whenFeeRecipientZeroAndFeeBpsZero(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Set both fee recipient and fee bps to zero - this should be valid
        paymentDetails.feeRecipient = address(0);
        paymentDetails.feeBps = 0;

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Verify balances - full amount should go to escrow since fees are 0
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + amount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 valueToConfirm) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(valueToConfirm > 0 && valueToConfirm <= authorizedAmount);

        mockERC3009Token.mint(buyerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentAuthorized(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.buyer,
            paymentDetails.captureAddress,
            paymentDetails.token,
            valueToConfirm
        );

        // Execute confirmation
        vm.prank(operator);
        paymentEscrow.authorize(valueToConfirm, paymentDetails, signature);
    }
}
