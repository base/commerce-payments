// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RegisterApprovalTest is PaymentEscrowBase {
    function test_succeeds_whenCalledByBuyer(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // Set up ERC20 approval first
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash, amount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);
    }

    function test_reverts_whenCalledByNonBuyer() public {
        uint256 amount = 100e6;
        address nonBuyer = makeAddr("nonBuyer");

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(nonBuyer);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, nonBuyer));
        paymentEscrow.registerApproval(paymentDetails);
    }

    function test_reverts_whenAuthorizationIsVoided() public {
        uint256 amount = 100e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // First void the authorization
        vm.prank(operator);
        paymentEscrow.void(paymentDetails);

        vm.prank(buyerEOA);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.VoidAuthorization.selector, paymentDetailsHash));
        paymentEscrow.registerApproval(paymentDetails);
    }

    function test_reverts_whenNoERC20Approval() public {
        uint256 amount = 100e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // Don't approve any tokens
        vm.prank(buyerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InsufficientApproval.selector, paymentDetailsHash, 0, amount)
        );
        paymentEscrow.registerApproval(paymentDetails);
    }

    function test_reverts_whenInsufficientERC20Approval() public {
        uint256 amount = 100e6;
        uint256 approvedAmount = amount - 1; // Approve less than required

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // Approve less than the payment amount
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), approvedAmount);

        vm.prank(buyerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentEscrow.InsufficientApproval.selector, paymentDetailsHash, approvedAmount, amount
            )
        );
        paymentEscrow.registerApproval(paymentDetails);
    }

    function test_succeeds_whenRegisteringMultipleTimes() public {
        uint256 amount = 100e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // Set up ERC20 approval
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // First registration
        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);

        // Second registration (should succeed with same event)
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash, amount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(paymentDetails);
    }
}
