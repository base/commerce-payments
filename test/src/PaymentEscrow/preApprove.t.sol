// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotpayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Now try to pre-approve
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        vm.prank(payerEOA);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyAuthorized.selector, paymentDetailsHash));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_succeeds_ifCalledBypayer(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        vm.prank(payerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Verify state change by trying to authorize with empty signature
        mockERC3009Token.mint(payerEOA, amount);
        vm.startPrank(payerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);
        vm.stopPrank();

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, ""); // ERC20Approval should work after pre-approval
    }

    function test_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.startPrank(payerEOA);
        paymentEscrow.preApprove(paymentDetails);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.PaymentAlreadyPreApproved.selector, paymentDetailsHash));
        paymentEscrow.preApprove(paymentDetails);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash);

        vm.prank(payerEOA);
        paymentEscrow.preApprove(paymentDetails);
    }
}
