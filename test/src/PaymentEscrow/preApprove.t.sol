// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotBuyer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != buyerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);
        mockERC3009Token.mint(buyerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Now try to pre-approve
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        vm.prank(buyerEOA);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyAuthorized.selector, paymentDetailsHash));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_succeeds_ifCalledByBuyer(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Verify state change by trying to authorize with empty signature
        mockERC3009Token.mint(buyerEOA, amount);
        vm.startPrank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);
        vm.stopPrank();

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, ""); // ERC20Approval should work after pre-approval
    }

    function test_reverts_ifCalledByBuyerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.startPrank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyPreApproved.selector, paymentDetailsHash));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash);

        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);
    }
}
