// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RefundTest is PaymentEscrowBase {
    function test_refund_succeeds_whenCalledByOperator(uint256 authorizedAmount, uint256 refundAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            authorizedAmount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails);
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

    function test_refund_succeeds_whenCalledByCaptureAddress(uint256 authorizedAmount, uint256 refundAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(refundAmount > 0 && refundAmount <= authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            authorizedAmount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails);
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

    function test_refund_reverts_whenRefundExceedsCaptured(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= buyerBalance); // Changed from > 0 to > 1
        uint256 chargeAmount = authorizedAmount / 2; // Charge only half
        uint256 refundAmount = authorizedAmount; // Try to refund full amount

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            authorizedAmount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        // First confirm and capture partial amount
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(chargeAmount, paymentDetails);
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

    function test_refund_reverts_whenNotOperatorOrCaptureAddress() public {
        uint256 authorizedAmount = 100e6;
        uint256 refundAmount = 60e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, randomAddress));
        paymentEscrow.refund(refundAmount, paymentDetails);
    }

    function test_refund_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 refundAmount = 60e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            authorizedAmount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        // First confirm and capture the payment
        vm.startPrank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, signature);
        paymentEscrow.capture(authorizedAmount, paymentDetails);
        vm.stopPrank();

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(paymentEscrow), refundAmount);

        // Record expected event
        vm.expectEmit(true, true, false, true);
        emit PaymentEscrow.PaymentRefunded(paymentDetailsHash, operator, refundAmount);

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(refundAmount, paymentDetails);
    }
}
