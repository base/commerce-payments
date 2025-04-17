// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract PreApprovalPaymentCollectorTest is PaymentEscrowBase {
    function test_collectTokens_reverts_whenCalledByNonPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        preApprovalPaymentCollector.collectTokens(paymentInfo, amount, "");
    }

    function test_reverts_ifTokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to authorize without pre-approval
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentNotPreApproved.selector, paymentInfoHash)
        );
        vm.prank(address(paymentEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(preApprovalPaymentCollector), amount);
        vm.prank(payerEOA);
        preApprovalPaymentCollector.preApprove(paymentInfo);
        vm.prank(address(paymentEscrow));
        preApprovalPaymentCollector.collectTokens(paymentInfo, amount, "");
    }
}
