// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract ReclaimTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotBuyer(address invalidSender, uint256 amount) public {
        vm.assume(invalidSender != buyerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Try to reclaim with invalid sender
        vm.warp(paymentDetails.captureDeadline);
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.reclaim(paymentDetails);
    }

    function test_reverts_ifBeforeCaptureDeadline(uint256 amount, uint48 currentTime) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        uint48 captureDeadline = uint48(block.timestamp + 1 days);
        vm.assume(currentTime < captureDeadline);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        // Set both deadlines - ensure authorizeDeadline is before captureDeadline
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.authorizeDeadline = captureDeadline - 1 hours; // Set authorize deadline before capture deadline

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Try to reclaim before deadline
        vm.warp(currentTime);
        vm.prank(buyerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.BeforeCaptureDeadline.selector, currentTime, captureDeadline)
        );
        paymentEscrow.reclaim(paymentDetails);
    }

    function test_reverts_ifAuthorizedValueIsZero(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // Try to reclaim without any authorization
        vm.warp(paymentDetails.captureDeadline);
        vm.prank(buyerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, keccak256(abi.encode(paymentDetails)))
        );
        paymentEscrow.reclaim(paymentDetails);
    }

    function test_reverts_ifAlreadyReclaimed(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Reclaim the payment the first time
        vm.warp(paymentDetails.captureDeadline);
        vm.prank(buyerEOA);
        paymentEscrow.reclaim(paymentDetails);

        // Try to reclaim again
        vm.prank(buyerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, keccak256(abi.encode(paymentDetails)))
        );
        paymentEscrow.reclaim(paymentDetails);
    }

    function test_succeeds_ifCalledByBuyerAfterCaptureDeadline(uint256 amount, uint48 timeAfterDeadline) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        uint48 captureDeadline = uint48(block.timestamp + 1 days);
        vm.assume(timeAfterDeadline > captureDeadline);
        vm.assume(timeAfterDeadline < type(uint48).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        // Set both deadlines - ensure authorizeDeadline is before captureDeadline
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.authorizeDeadline = captureDeadline - 1 hours; // Set authorize deadline before capture deadline

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Reclaim after deadline
        vm.warp(timeAfterDeadline);
        vm.prank(buyerEOA);
        paymentEscrow.reclaim(paymentDetails);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore + amount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore - amount);
    }

    function test_emitsExpectedEvents(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Prepare for reclaim
        vm.warp(paymentDetails.captureDeadline);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentReclaimed(paymentDetailsHash, amount);

        vm.prank(buyerEOA);
        paymentEscrow.reclaim(paymentDetails);
    }
}
