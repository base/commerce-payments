// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AuthorizeWithERC3009Test is PaymentEscrowBase {
    function test_reverts_whenValueIsZero() public {
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1}); // Any non-zero value

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroAmount.selector);
        paymentEscrow.authorize(paymentDetails, 0, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_whenAmountOverflows(uint256 overflowValue) public {
        vm.assume(overflowValue > type(uint120).max);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1});

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.AmountOverflow.selector, overflowValue, type(uint120).max));
        paymentEscrow.authorize(paymentDetails, overflowValue, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_whenCallerIsNotOperator(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_whenValueExceedsAuthorized(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        uint256 confirmAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.ExceedsMaxAmount.selector, confirmAmount, authorizedAmount)
        );
        paymentEscrow.authorize(paymentDetails, confirmAmount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_exactlyAtPreApprovalExpiry(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 preApprovalExpiry = uint48(block.timestamp + 1 days);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
        paymentDetails.preApprovalExpiry = preApprovalExpiry;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // Set time to exactly at the authorize deadline
        vm.warp(preApprovalExpiry);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.AfterPreApprovalExpiry.selector, preApprovalExpiry, preApprovalExpiry)
        );
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_afterPreApprovalExpiry(uint120 amount) public {
        vm.assume(amount > 0);

        uint48 preApprovalExpiry = uint48(block.timestamp + 1 days);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
        paymentDetails.preApprovalExpiry = preApprovalExpiry;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // Set time to after the authorize deadline
        vm.warp(preApprovalExpiry + 1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.AfterPreApprovalExpiry.selector, preApprovalExpiry + 1, preApprovalExpiry
            )
        );
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
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

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentDetails.preApprovalExpiry = preApprovalExpiry;
        paymentDetails.authorizationExpiry = authorizationExpiry;
        paymentDetails.refundExpiry = refundExpiry;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
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

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set authorize deadline after capture deadline
        paymentDetails.preApprovalExpiry = preApprovalExpiry;
        paymentDetails.authorizationExpiry = authorizationExpiry;
        paymentDetails.refundExpiry = refundExpiry;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InvalidExpiries.selector, preApprovalExpiry, authorizationExpiry, refundExpiry
            )
        );
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_whenFeeBpsTooHigh(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set fee bps > 100%
        paymentDetails.maxFeeBps = 10_001;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.FeeBpsOverflow.selector, 10_001));
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_reverts_whenAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First authorization
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);

        // Try to authorize again with same payment details
        mockERC3009Token.mint(payerEOA, amount);
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyCollected.selector, paymentDetailsHash));
        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);
    }

    function test_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(amount > 0 && amount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(payerEOA, amount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), amount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
    }

    function test_authorize_succeeds_whenValueLessThanAuthorized(uint120 authorizedAmount, uint120 confirmAmount)
        public
    {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);
        vm.assume(confirmAmount > 0 && confirmAmount < authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);

        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, confirmAmount, hooks[TokenCollector.ERC3009], signature);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), confirmAmount);
        assertEq(
            mockERC3009Token.balanceOf(payerEOA),
            payerBalanceBefore - authorizedAmount + (authorizedAmount - confirmAmount)
        );
    }

    function test_succeeds_whenFeeRecipientZeroAndFeeBpsZero(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // Set both fee recipient and fee bps to zero - this should be valid
        paymentDetails.feeReceiver = address(0);
        paymentDetails.minFeeBps = 0;
        paymentDetails.maxFeeBps = 0;

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        mockERC3009Token.mint(payerEOA, amount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, amount, hooks[TokenCollector.ERC3009], signature);

        // Verify balances - full amount should go to escrow since fees are 0
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + amount);
    }

    function test_emitsCorrectEvents(uint120 authorizedAmount, uint120 valueToConfirm) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(valueToConfirm > 0 && valueToConfirm <= authorizedAmount);

        mockERC3009Token.mint(payerEOA, authorizedAmount);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // Record expected event
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentAuthorized(
            paymentDetailsHash,
            paymentDetails.operator,
            paymentDetails.payer,
            paymentDetails.receiver,
            paymentDetails.token,
            valueToConfirm,
            hooks[TokenCollector.ERC3009]
        );

        // Execute confirmation
        vm.prank(operator);
        paymentEscrow.authorize(paymentDetails, valueToConfirm, hooks[TokenCollector.ERC3009], signature);
    }
}
