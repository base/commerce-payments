// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotPayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender, paymentInfo.payer));
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        // Now try to pre-approve
        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentAlreadyCollected.selector, paymentInfoHash)
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_succeeds_ifCalledByPayer(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);

        // Verify state change by trying to authorize with empty signature
        mockERC3009Token.mint(payerEOA, amount);
        vm.startPrank(payerEOA);
        mockERC3009Token.approve(address(preApprovalPaymentCollector), amount);
        vm.stopPrank();

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(preApprovalPaymentCollector), ""); // ERC20Approval should work after pre-approval
    }

    function test_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        vm.startPrank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentAlreadyPreApproved.selector, paymentInfoHash)
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        vm.expectEmit(true, false, false, false);
        emit PreApprovalPaymentCollector.PaymentPreApproved(paymentInfoHash);

        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }
}
