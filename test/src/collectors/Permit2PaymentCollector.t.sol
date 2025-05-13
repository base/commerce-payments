// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";

import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {AuthCaptureEscrowSmartWalletBase} from "../../base/AuthCaptureEscrowSmartWalletBase.sol";

contract Permit2PaymentCollectorTest is AuthCaptureEscrowSmartWalletBase {
    function setUp() public override {
        super.setUp();
        vm.prank(address(smartWalletDeployed));
        mockERC20Token.approve(address(permit2), type(uint256).max);
        vm.prank(smartWalletCounterfactual);
        mockERC20Token.approve(address(permit2), type(uint256).max);
    }

    function test_collectTokens_reverts_whenCalledByNonAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyAuthCaptureEscrow.selector));
        permit2PaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        bytes memory signature = _signPermit2Transfer({
            token: address(mockERC3009Token),
            amount: amount,
            deadline: paymentInfo.preApprovalExpiry,
            nonce: uint256(_getHashPayerAgnostic(paymentInfo)),
            privateKey: payer_EOA_PK
        });
        vm.prank(address(authCaptureEscrow));
        permit2PaymentCollector.collectTokens(paymentInfo, tokenStore, amount, signature);
    }

    function test_collectTokens_succeeds_withERC6492Signature(uint120 amount) public {
        vm.assume(amount > 0);

        mockERC20Token.mint(smartWalletCounterfactual, amount);

        assertEq(smartWalletCounterfactual.code.length, 0, "Smart wallet should not be deployed yet");

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(smartWalletCounterfactual, amount, address(mockERC20Token));
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);

        bytes memory signature = _signPermit2WithERC6492(paymentInfo, COUNTERFACTUAL_WALLET_OWNER_PK, 0);

        vm.prank(address(authCaptureEscrow));
        permit2PaymentCollector.collectTokens(paymentInfo, tokenStore, amount, signature);

        assertEq(
            mockERC20Token.balanceOf(authCaptureEscrow.getTokenStore(paymentInfo.operator)),
            amount,
            "Token store balance did not increase by correct amount"
        );
        assertEq(mockERC20Token.balanceOf(smartWalletCounterfactual), 0, "Smart wallet balance should be 0");
    }
}
