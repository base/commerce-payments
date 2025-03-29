// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {PreApprovalTokenCollector} from "../../../src/collectors/PreApprovalTokenCollector.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotpayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);
    }

    function test_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, hooks[TokenCollector.ERC3009], signature);
        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);
        // Now try to pre-approve
        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalTokenCollector.PaymentAlreadyCollected.selector, paymentDetailsHash)
        );
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);
    }

    function test_succeeds_ifCalledByPayer(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);

        // Verify state change by trying to authorize with empty signature
        mockERC3009Token.mint(payerEOA, amount);
        vm.startPrank(payerEOA);
        mockERC3009Token.approve(address(hooks[TokenCollector.ERC20]), amount);
        vm.stopPrank();

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, hooks[TokenCollector.ERC20], ""); // ERC20Approval should work after pre-approval
    }

    function test_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);

        vm.startPrank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalTokenCollector.PaymentAlreadyPreApproved.selector, paymentDetailsHash)
        );
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});

        bytes32 paymentDetailsHash = paymentEscrow.getHash(paymentDetails);

        vm.expectEmit(true, false, false, false);
        emit PreApprovalTokenCollector.PaymentApproved(paymentDetailsHash);

        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);
    }
}
