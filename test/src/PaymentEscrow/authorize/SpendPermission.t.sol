// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";

contract AuthorizeWithSpendPermissionTest is PaymentEscrowSmartWalletBase {
    function test_succeeds_withDeployedSmartWallet(uint256 amount) public {
        // Get wallet's current balance
        uint256 walletBalance = mockERC3009Token.balanceOf(address(smartWalletDeployed));

        // Assume reasonable values
        vm.assume(amount > 0 && amount <= walletBalance);

        // Create payment details with SpendPermission auth type
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(address(smartWalletDeployed), amount);
        paymentDetails.authType = PaymentEscrow.AuthorizationType.SpendPermission;

        // Create and sign the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(
            address(smartWalletDeployed),
            captureAddress,
            amount,
            paymentDetails.authorizeDeadline,
            paymentDetails.captureDeadline
        );

        bytes memory signature = _signSpendPermission(
            permission,
            DEPLOYED_WALLET_OWNER_PK,
            0 // owner index
        );

        // Record balances before
        uint256 walletBalanceBefore = mockERC3009Token.balanceOf(address(smartWalletDeployed));
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Submit authorization
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Verify balances
        assertEq(
            mockERC3009Token.balanceOf(address(smartWalletDeployed)),
            walletBalanceBefore - amount,
            "Wallet balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(address(paymentEscrow)),
            escrowBalanceBefore + amount,
            "Escrow balance should increase by amount"
        );
    }
}
