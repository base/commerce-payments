// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {MockRevertOnTransferToken} from "../../mocks/MockRevertOnTransferToken.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract CaptureTest is PaymentEscrowBase {
    function test_reverts_whenNotOperator(uint120 authorizedAmount, address sender) public {
        vm.assume(authorizedAmount > 0);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        vm.assume(sender != paymentInfo.operator);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, sender, paymentInfo.operator));
        paymentEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroAmount.selector);
        paymentEscrow.capture(paymentInfo, 0, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: 1});

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.AmountOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.capture(paymentInfo, overflowValue, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_whenAfterAuthorizationExpiry(
        uint120 authorizedAmount,
        uint120 captureAmount,
        uint48 authorizationExpiry
    ) public {
        vm.assume(authorizationExpiry > 1 && authorizationExpiry < type(uint40).max);
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(captureAmount > 0 && captureAmount <= authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.preApprovalExpiry = authorizationExpiry;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.warp(paymentInfo.preApprovalExpiry - 1);
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.warp(authorizationExpiry + 1);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterAuthorizationExpiry.selector, block.timestamp, authorizationExpiry
            )
        );
        paymentEscrow.capture(paymentInfo, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_whenInsufficientAuthorization(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        uint256 captureAmount = authorizedAmount + 1; // Try to capture more than authorized

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Try to capture more than authorized
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InsufficientAuthorization.selector, paymentInfoHash, authorizedAmount, captureAmount
            )
        );
        paymentEscrow.capture(paymentInfo, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_receiverSender(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Then capture the full amount
        vm.prank(paymentInfo.receiver);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, paymentInfo.receiver, paymentInfo.operator)
        );
        paymentEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
    }

    function test_succeeds_withFullAmount(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        uint256 feeAmount = authorizedAmount * FEE_BPS / 10_000;
        uint256 receiverExpectedBalance = authorizedAmount - feeAmount;

        // Then capture the full amount
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_succeeds_withPartialAmount(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 1 && authorizedAmount <= payerBalance);
        uint256 captureAmount = authorizedAmount / 2;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        uint256 feeAmount = captureAmount * FEE_BPS / 10_000;
        uint256 receiverExpectedBalance = captureAmount - feeAmount;

        // Then capture partial amount
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);

        // Verify balances and state
        address operatorTokenStore = paymentEscrow.getTokenStore(operator);
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), authorizedAmount - captureAmount);
    }

    function test_succeeds_withMultipleCaptures(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 2 && authorizedAmount <= payerBalance);
        uint256 firstCaptureAmount = authorizedAmount / 2;
        uint256 secondCaptureAmount = authorizedAmount - firstCaptureAmount;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // First capture
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, firstCaptureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);

        // Second capture
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, secondCaptureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);

        // Calculate fees for each capture separately to match contract behavior
        uint256 firstFeesAmount = firstCaptureAmount * FEE_BPS / 10_000;
        uint256 secondFeesAmount = secondCaptureAmount * FEE_BPS / 10_000;
        uint256 totalFeeAmount = firstFeesAmount + secondFeesAmount;

        // Calculate expected capture address balance by subtracting fees from each capture
        uint256 receiverExpectedBalance =
            (firstCaptureAmount - firstFeesAmount) + (secondCaptureAmount - secondFeesAmount);

        // Verify final state
        assertEq(mockERC3009Token.balanceOf(receiver), receiverExpectedBalance);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), totalFeeAmount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_emitsCorrectEvents() public {
        uint120 authorizedAmount = 100e9;
        uint120 captureAmount = 60e9;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentCaptured(
            paymentInfoHash, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver
        );

        // Execute capture
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, captureAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
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

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.capture(paymentInfo, authorizedAmount, captureFeeBps, paymentInfo.feeReceiver);
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

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.FeeBpsOutOfRange.selector, captureFeeBps, minFeeBps, maxFeeBps)
        );
        paymentEscrow.capture(paymentInfo, authorizedAmount, captureFeeBps, paymentInfo.feeReceiver);
    }

    function test_reverts_whenFeeReceiverInvalid(
        uint120 authorizedAmount,
        uint16 minFeeBps,
        uint16 maxFeeBps,
        uint16 captureFeeBps,
        address invalidFeeReceiver
    ) public {
        // Assume reasonable bounds for fees
        vm.assume(authorizedAmount > 0);
        vm.assume(minFeeBps > 0);
        vm.assume(maxFeeBps >= minFeeBps && maxFeeBps < 10000);
        vm.assume(captureFeeBps >= minFeeBps && captureFeeBps <= maxFeeBps);
        vm.assume(invalidFeeReceiver != address(0));
        vm.assume(invalidFeeReceiver != feeReceiver);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;
        paymentInfo.feeReceiver = feeReceiver;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidFeeReceiver.selector, invalidFeeReceiver, feeReceiver)
        );
        paymentEscrow.capture(paymentInfo, authorizedAmount, captureFeeBps, invalidFeeReceiver);
    }

    function test_reverts_ifSendTokensReverts(uint120 authorizedAmount) public {
        vm.assume(authorizedAmount > 0);
        address revertingToken = address(new MockRevertOnTransferToken(address(preApprovalPaymentCollector)));
        MockRevertOnTransferToken(revertingToken).mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.token = revertingToken;

        vm.prank(payerEOA);
        MockRevertOnTransferToken(revertingToken).approve(address(preApprovalPaymentCollector), authorizedAmount);
        vm.prank(payerEOA);
        preApprovalPaymentCollector.preApprove(paymentInfo);

        vm.startPrank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(preApprovalPaymentCollector), "");

        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        paymentEscrow.capture(paymentInfo, authorizedAmount, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();
    }

    function test_reverts_whenFeeBpsAreZeroAndFeeReceiverIsNonzero(uint120 authorizedAmount, address feeReceiver)
        public
    {
        // Assume reasonable bounds for fees
        vm.assume(authorizedAmount > 0);
        vm.assume(feeReceiver != address(0));
        assumePayable(feeReceiver);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);
        paymentInfo.minFeeBps = 0;
        paymentInfo.maxFeeBps = 0;
        paymentInfo.feeReceiver = address(0);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ZeroFeeBps.selector));
        paymentEscrow.capture(paymentInfo, authorizedAmount, 0, feeReceiver);
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
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: authorizedAmount, token: address(mockERC3009Token)});
        paymentInfo.feeReceiver = address(0);
        paymentInfo.minFeeBps = minFeeBps;
        paymentInfo.maxFeeBps = maxFeeBps;

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        vm.prank(paymentInfo.operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        address newFeeRecipient = address(0xdead);

        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, authorizedAmount, captureFeeBps, newFeeRecipient);

        uint256 feeAmount = (uint256(authorizedAmount) * uint256(captureFeeBps)) / 10_000;
        assertEq(mockERC3009Token.balanceOf(newFeeRecipient), feeAmount);
        assertEq(mockERC3009Token.balanceOf(receiver), authorizedAmount - feeAmount);
    }
}
