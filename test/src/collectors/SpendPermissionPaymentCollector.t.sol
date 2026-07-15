// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MagicSpend} from "magicspend/MagicSpend.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {SpendPermissionPaymentCollector} from "../../../src/collectors/SpendPermissionPaymentCollector.sol";

import {AuthCaptureEscrowSmartWalletBase} from "../../base/AuthCaptureEscrowSmartWalletBase.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";

contract SpendPermissionPaymentCollectorTest is AuthCaptureEscrowSmartWalletBase {
    function test_collectTokens_reverts_whenCalledByNonAuthCaptureEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyAuthCaptureEscrow.selector));
        spendPermissionPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, "");
    }

    function test_collectTokens_reverts_whenSpendPermissionApprovalFails(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(address(smartWalletDeployed), amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
            payer: address(smartWalletDeployed),
            maxAmount: amount,
            token: address(mockERC3009Token)
        });
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);

        // Create spend permission but sign with wrong private key to force approval failure
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);
        vm.prank(address(smartWalletDeployed));
        spendPermissionManager.revoke(permission); // pre-revoke to force approval failure
        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        vm.expectRevert(SpendPermissionPaymentCollector.SpendPermissionApprovalFailed.selector);
        vm.prank(address(authCaptureEscrow));
        spendPermissionPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, abi.encode(signature, ""));
    }

    function test_collectTokens_succeeds_withBasicSpend(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(address(smartWalletDeployed), amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
            payer: address(smartWalletDeployed),
            maxAmount: amount,
            token: address(mockERC3009Token)
        });
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);

        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);
        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        vm.prank(address(authCaptureEscrow));
        spendPermissionPaymentCollector.collectTokens(paymentInfo, tokenStore, amount, abi.encode(signature, ""));

        // Verify tokens were transferred to token store
        assertEq(mockERC3009Token.balanceOf(tokenStore), amount, "Token store should have received tokens");
    }

    function test_collectTokens_succeeds_withMagicSpendWithdraw(uint120 amount) public {
        vm.assume(amount > 0);
        // Fund MagicSpend instead of the smart wallet
        mockERC3009Token.mint(address(magicSpend), amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
            payer: address(smartWalletDeployed),
            maxAmount: amount,
            token: address(mockERC3009Token)
        });
        address tokenStore = authCaptureEscrow.getTokenStore(paymentInfo.operator);

        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);
        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        // Create and sign withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission);
        withdrawRequest.asset = address(mockERC3009Token);
        withdrawRequest.amount = amount;
        withdrawRequest.signature = _signWithdrawRequest(address(smartWalletDeployed), withdrawRequest);

        // Record balances before
        uint256 magicSpendBalanceBefore = mockERC3009Token.balanceOf(address(magicSpend));

        vm.prank(address(authCaptureEscrow));
        spendPermissionPaymentCollector.collectTokens(
            paymentInfo, tokenStore, amount, abi.encode(signature, abi.encode(withdrawRequest))
        );

        // Verify balances - funds should move from MagicSpend to token store
        assertEq(
            mockERC3009Token.balanceOf(address(magicSpend)),
            magicSpendBalanceBefore - amount,
            "MagicSpend balance should decrease by amount"
        );
        assertEq(mockERC3009Token.balanceOf(tokenStore), amount, "Token store balance should increase by amount");
    }
}
