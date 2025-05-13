// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";

import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract OperatorRefundCollectorTest is AuthCaptureEscrowBase {
    function test_collectTokens_reverts_whenCalledByNonAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyAuthCaptureEscrow.selector));
        operatorRefundCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(operator, amount);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.prank(operator);
        mockERC3009Token.approve(address(operatorRefundCollector), amount);
        vm.prank(address(authCaptureEscrow));
        operatorRefundCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }
}
