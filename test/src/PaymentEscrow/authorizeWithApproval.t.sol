// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract AuthorizeFromApprovalTest is PaymentEscrowBase {
    function test_succeeds_whenValueEqualsAuthorized(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        // Set up approval and register it
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(amount, paymentDetails);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), amount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }

    function test_succeeds_whenValueLessThanAuthorized(uint256 authorizedAmount, uint256 confirmAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        vm.assume(confirmAmount > 0 && confirmAmount < authorizedAmount);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        bytes memory paymentDetails = abi.encode(auth);

        // Set up approval and register it
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), authorizedAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);

        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(confirmAmount, paymentDetails);

        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), confirmAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - confirmAmount);
    }

    function test_reverts_whenValueExceedsAuthorized(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);
        uint256 confirmAmount = authorizedAmount + 1; // Always exceeds authorized

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), authorizedAmount);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueLimitExceeded.selector, confirmAmount));
        paymentEscrow.authorizeFromApproval(confirmAmount, paymentDetails);
    }

    function test_reverts_whenAuthorizationIsVoided(uint256 authorizedAmount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(authorizedAmount > 0 && authorizedAmount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), authorizedAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        // Void the authorization
        vm.prank(operator);
        paymentEscrow.void(paymentDetails);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.VoidAuthorization.selector, paymentDetailsHash));
        paymentEscrow.authorizeFromApproval(authorizedAmount, paymentDetails);
    }

    function test_reverts_whenInsufficientApproval(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        // Don't approve tokens
        vm.prank(operator);
        vm.expectRevert(); // ERC20 insufficient allowance error
        paymentEscrow.authorizeFromApproval(amount, paymentDetails);
    }

    function test_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;
        uint256 valueToConfirm = 60e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, authorizedAmount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), authorizedAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentAuthorized(paymentDetailsHash, valueToConfirm);

        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(valueToConfirm, paymentDetails);
    }

    function test_succeeds_withMultipleAuthorizations() public {
        uint256 totalAmount = 100e6;
        uint256 firstAuth = 40e6;
        uint256 secondAuth = 30e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, totalAmount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), totalAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // First authorization
        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(firstAuth, paymentDetails);

        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - firstAuth);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + firstAuth);

        // Second authorization
        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(secondAuth, paymentDetails);

        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - firstAuth - secondAuth);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + firstAuth + secondAuth);
    }

    function test_reverts_whenUsingApprovalForDifferentPayment() public {
        uint256 amount = 100e6;

        // Create two different payment details though for the same buyer
        PaymentEscrow.Authorization memory auth1 = _createPaymentEscrowAuthorization(buyerEOA, amount);
        PaymentEscrow.Authorization memory auth2 = _createPaymentEscrowAuthorization(buyerEOA, amount);
        auth2.salt = 1; // Make hash different

        bytes memory paymentDetails1 = abi.encode(auth1);
        bytes memory paymentDetails2 = abi.encode(auth2);
        bytes32 paymentDetailsHash1 = keccak256(paymentDetails1);
        bytes32 paymentDetailsHash2 = keccak256(paymentDetails2);

        // Setup approval and register it for first payment
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails1);

        // Try to authorize against different payment details
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InsufficientApproval.selector, paymentDetailsHash2, 0, amount)
        );
        paymentEscrow.authorizeFromApproval(amount, paymentDetails2);
    }

    function test_reverts_whenAuthorizingMoreThanRemainingApproval() public {
        uint256 totalAmount = 100e6;
        uint256 firstAuth = 70e6;
        uint256 secondAuth = 40e6; // Would exceed remaining approval

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, totalAmount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // Setup approval and register it
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), totalAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        // First authorization succeeds
        vm.prank(operator);
        paymentEscrow.authorizeFromApproval(firstAuth, paymentDetails);

        // Second authorization fails due to insufficient remaining approval
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InsufficientApproval.selector, paymentDetailsHash, totalAmount - firstAuth, secondAuth
            )
        );
        paymentEscrow.authorizeFromApproval(secondAuth, paymentDetails);
    }
}
