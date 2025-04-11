// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract ChargeWithERC3009Test is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroAmount.selector);
        paymentEscrow.charge(
            paymentInfo, 0, address(erc3009PaymentCollector), signature, paymentInfo.minFeeBps, paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1});

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.AmountOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.charge(
            paymentInfo,
            overflowValue,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenCallerIsNotOperator(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != receiver);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender, paymentInfo.operator)
        );
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenValueExceedsAuthorized(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        uint256 chargeAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        vm.warp(paymentInfo.authorizationExpiry - 1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ExceedsMaxAmount.selector, chargeAmount, authorizedAmount));
        paymentEscrow.charge(
            paymentInfo,
            chargeAmount,
            address(erc3009PaymentCollector),
            "",
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenAfterPreApprovalExpiry(uint120 amount, uint48 authorizationExpiry) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);
        vm.assume(amount > 0 && amount <= payerBalance);
        vm.assume(authorizationExpiry > 0 && authorizationExpiry < type(uint48).max);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, amount);
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.preApprovalExpiry = authorizationExpiry;

        // Set time to after the capture deadline
        vm.warp(authorizationExpiry + 1);

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterPreApprovalExpiry.selector, uint48(block.timestamp), paymentInfo.preApprovalExpiry
            )
        );
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenPreApprovalExpiryAfterAuthorizationExpiry(
        uint120 amount,
        uint48 preApprovalExpiry,
        uint48 authorizationExpiry,
        uint48 refundExpiry
    ) public {
        vm.assume(amount > 0);
        vm.assume(preApprovalExpiry > block.timestamp);
        vm.assume(preApprovalExpiry > authorizationExpiry);
        vm.assume(authorizationExpiry <= refundExpiry);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentInfo.preApprovalExpiry = preApprovalExpiry;
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.refundExpiry = refundExpiry;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenAuthorizationExpiryAfterRefundExpiry(
        uint120 amount,
        uint48 preApprovalExpiry,
        uint48 authorizationExpiry,
        uint48 refundExpiry
    ) public {
        vm.assume(amount > 0);
        vm.assume(preApprovalExpiry > block.timestamp);
        vm.assume(preApprovalExpiry <= authorizationExpiry);
        vm.assume(authorizationExpiry > refundExpiry);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentInfo.preApprovalExpiry = preApprovalExpiry;
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.refundExpiry = refundExpiry;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        // First authorization
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Try to charge now with same payment info
        mockERC3009Token.mint(payerEOA, amount);
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyCollected.selector, paymentInfoHash));
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(amount > 0 && amount <= payerBalance);
        mockERC3009Token.mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, amount);
        vm.warp(paymentInfo.authorizationExpiry - 1);

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );

        uint256 feeAmount = amount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(receiver), amount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
    }

    function test_succeeds_whenValueLessThanAuthorized(uint120 authorizedAmount, uint120 chargeAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(chargeAmount > 0 && chargeAmount < authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            chargeAmount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );

        uint256 feeAmount = chargeAmount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(receiver), chargeAmount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - chargeAmount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 valueToCharge) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(valueToCharge > 0 && valueToCharge <= authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        vm.warp(paymentInfo.authorizationExpiry - 1);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentCharged(
            paymentInfoHash,
            paymentInfo.operator,
            paymentInfo.payer,
            paymentInfo.receiver,
            paymentInfo.token,
            valueToCharge,
            address(erc3009PaymentCollector)
        );

        // Execute charge
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            valueToCharge,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );
    }

    function test_allowsRefund(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 3 && authorizedAmount <= payerBalance);

        uint256 chargeAmount = authorizedAmount / 2;
        uint256 refundAmount = chargeAmount / 2;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);
        vm.warp(paymentInfo.authorizationExpiry - 1);

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        // First charge the payment
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            chargeAmount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );

        // Fund operator for refund
        mockERC3009Token.mint(operator, refundAmount);
        vm.prank(operator);
        mockERC3009Token.approve(address(operatorRefundCollector), refundAmount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 operatorBalanceBefore = mockERC3009Token.balanceOf(operator);

        // Execute refund
        vm.prank(operator);
        paymentEscrow.refund(paymentInfo, refundAmount, address(operatorRefundCollector), "");

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(operator), operatorBalanceBefore - refundAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + refundAmount);

        // Try to refund more than remaining captured amount
        uint256 remainingCaptured = chargeAmount - refundAmount;
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, chargeAmount, remainingCaptured)
        );
        vm.prank(operator);
        paymentEscrow.refund(paymentInfo, chargeAmount, address(operatorRefundCollector), "");
    }

    function test_reverts_whenFeeBpsBelowMin(uint120 amount, uint16 minFeeBps, uint16 maxFeeBps, uint16 captureFeeBps)
        public
    {
        // Assume reasonable bounds for fees
        vm.assume(amount > 0);
        vm.assume(minFeeBps > 0);
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps < 10000);
        vm.assume(captureFeeBps < minFeeBps); // Must be below min to trigger revert

        mockERC3009Token.mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.charge(
            paymentInfo, amount, address(erc3009PaymentCollector), signature, captureFeeBps, paymentInfo.feeReceiver
        );
    }

    function test_charge_reverts_whenFeeBpsAboveMax(
        uint120 amount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps
    ) public {
        // Assume reasonable bounds for fees
        vm.assume(amount > 0);
        vm.assume(maxFeeBps < 10000); // Keep maxFeeBps within valid range
        vm.assume(minFeeBps <= maxFeeBps);
        vm.assume(captureFeeBps > maxFeeBps && captureFeeBps <= 10000); // Must be above max but within bounds

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.charge(
            paymentInfo, amount, address(erc3009PaymentCollector), signature, captureFeeBps, paymentInfo.feeReceiver
        );
    }

    function test_reverts_whenFeeRecipientZeroWithNonZeroFee(uint120 amount, uint16 minFeeBps, uint16 maxFeeBps)
        public
    {
        vm.assume(amount > 0);
        vm.assume(minFeeBps > 0);
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps <= 10000);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        paymentInfo.feeReceiver = address(0); // Allow operator to set fee recipient
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroFeeReceiver.selector);
        paymentEscrow.charge(paymentInfo, amount, address(erc3009PaymentCollector), signature, minFeeBps, address(0));
    }

    function test_succeeds_withOperatorSetFeeRecipient(
        uint120 amount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps,
        address newFeeRecipient
    ) public {
        // Assume reasonable bounds for fees
        vm.assume(amount > 0);
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps <= 10000);
        vm.assume(captureFeeBps >= minFeeBps && captureFeeBps <= maxFeeBps); // Must be within range

        mockERC3009Token.mint(payerEOA, amount);

        // Ensure newFeeRecipient is not zero address or other special addresses
        assumePayable(newFeeRecipient);
        vm.assume(newFeeRecipient != address(0));
        vm.assume(newFeeRecipient != address(paymentEscrow));
        vm.assume(newFeeRecipient != receiver);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        paymentInfo.feeReceiver = address(0); // Allow operator to set fee recipient
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo, amount, address(erc3009PaymentCollector), signature, captureFeeBps, newFeeRecipient
        );

        uint256 feeAmount = (uint256(amount) * uint256(captureFeeBps)) / 10_000;
        assertEq(mockERC3009Token.balanceOf(newFeeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(receiver), amount - feeAmount);
    }
}
