// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract ConfirmAuthorizationTest is PaymentEscrowBase {
    function test_reverts_ifSignatureIsEmptyAndTokenIsNotPreApproved() public {}
    function test_reverts_ifSignatureIsEmptyAndTokenIsPreApprovedButFundsAreNotTransferred() public {}
    function test_succeeds_ifSignatureIsNotEmptyAndTokenIsPreApproved() public {}

    function test_authorize_succeeds_whenValueEqualsAuthorized(uint256 amount) public {
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

    function test_authorize_succeeds_whenValueLessThanAuthorized(uint256 authorizedAmount, uint256 confirmAmount)
        public
    {
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

    function test_authorize_reverts_whenValueExceedsAuthorized(uint256 authorizedAmount) public {
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

    function test_authorize_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 valueToConfirm = 60e6; // Confirm less than authorized to test refund events

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
