// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract PreApprovalPaymentCollectorTest is AuthCaptureEscrowBase {
    // ======= preApprove =======

    function test_preApprove_reverts_ifSenderIsNotPayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.InvalidSender.selector, invalidSender, paymentInfo.payer)
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_preApprove_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        // Now try to pre-approve
        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentAlreadyCollected.selector, paymentInfoHash)
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_preApprove_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        vm.startPrank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentAlreadyPreApproved.selector, paymentInfoHash)
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_preApprove_reverts_ifAfterPreApprovalExpiry(uint120 amount) public {
        vm.assume(amount > 0);

        // Create payment info with a pre-approval expiry in the past
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        paymentInfo.preApprovalExpiry = uint48(block.timestamp - 1);

        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthCaptureEscrow.AfterPreApprovalExpiry.selector,
                uint48(block.timestamp),
                paymentInfo.preApprovalExpiry
            )
        );
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    function test_preApprove_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        vm.expectEmit(true, false, false, false);
        emit PreApprovalPaymentCollector.PaymentPreApproved(paymentInfoHash);

        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);
    }

    // ======= collectTokens =======
    function test_collectTokens_reverts_whenCalledByNonAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyAuthCaptureEscrow.selector));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_reverts_ifTokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(authCaptureEscrow), amount);

        // Try to authorize without pre-approval
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentNotPreApproved.selector, paymentInfoHash)
        );
        vm.prank(address(authCaptureEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(preApprovalPaymentCollector), amount);
        vm.prank(payerEOA);
        preApprovalPaymentCollector.preApprove(paymentInfo);
        vm.prank(address(authCaptureEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }
}
