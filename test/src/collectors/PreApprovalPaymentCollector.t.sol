// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract PreApprovalPaymentCollectorTest is PaymentEscrowBase {
    // ======= preApprove =======

    function test_preApprove_reverts_ifSenderIsNotPayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender, paymentInfo.payer));
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_preApprove_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
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

    function test_preApprove_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
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

    function test_preApprove_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        vm.expectEmit(true, false, false, false);
        emit PreApprovalPaymentCollector.PaymentPreApproved(paymentInfoHash);

        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    // ======= collectTokens =======
    function test_collectTokens_reverts_whenCalledByNonPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_reverts_ifTokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to authorize without pre-approval
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentNotPreApproved.selector, paymentInfoHash)
        );
        vm.prank(address(paymentEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(preApprovalPaymentCollector), amount);
        vm.prank(payerEOA);
        preApprovalPaymentCollector.preApprove(paymentInfo);
        vm.prank(address(paymentEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }
}
