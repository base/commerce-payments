// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract ChargeTest is PaymentEscrowBase {
    function test_charge_succeeds_whenValueEqualsAuthorized(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(buyerEOA, amount);
        vm.warp(paymentDetails.captureDeadline - 1);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            amount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.charge(amount, paymentDetails, signature);

        uint256 feeAmount = amount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), amount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }

    function test_charge_succeeds_whenValueLessThanAuthorized(uint256 authorizedAmount, uint256 chargeAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(chargeAmount > 0 && chargeAmount < authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

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

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.charge(chargeAmount, paymentDetails, signature);

        uint256 feeAmount = chargeAmount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), chargeAmount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - chargeAmount);
    }

    function test_charge_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 valueToCharge = 60e6; // Charge less than authorized to test refund events

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

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

    function test_charge_allowsRefund(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 3 && authorizedAmount <= buyerBalance);

        uint256 chargeAmount = authorizedAmount / 2;
        uint256 refundAmount = chargeAmount / 2;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        vm.warp(paymentDetails.captureDeadline - 1);

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

    function test_charge_reverts_whenValueExceedsAuthorized(uint256 authorizedAmount) public {
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

    function test_charge_reverts_afterCaptureDeadline(uint256 authorizedAmount, uint48 captureDeadline) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(captureDeadline < type(uint48).max);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        uint256 chargeAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        paymentDetails.captureDeadline = captureDeadline;
        vm.warp(captureDeadline + 1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueLimitExceeded.selector, chargeAmount));
        paymentEscrow.charge(chargeAmount, paymentDetails, "");
    }

    function test_charge_reverts_whenAfterAuthorizationDeadline(uint256 amount, uint48 captureDeadline) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);
        vm.assume(captureDeadline > 0 && captureDeadline < type(uint48).max);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(buyerEOA, amount);
        paymentDetails.captureDeadline = captureDeadline;
        paymentDetails.validBefore = captureDeadline;

        // Set time to after the capture deadline
        vm.warp(captureDeadline + 1);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signERC3009(
            buyerEOA,
            address(paymentEscrow),
            amount,
            paymentDetails.validAfter,
            paymentDetails.validBefore,
            paymentDetailsHash,
            BUYER_EOA_PK
        );

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationDeadline.selector, uint48(block.timestamp), paymentDetails.validBefore
            )
        );
        paymentEscrow.charge(amount, paymentDetails, signature);
    }
}
