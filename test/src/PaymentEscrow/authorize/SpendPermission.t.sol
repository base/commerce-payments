// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";

contract AuthorizeWithSpendPermissionTest is PaymentEscrowSmartWalletBase {
    function test_succeeds_withDeployedSmartWallet(uint256 maxAmount, uint256 amount) public {
        // Get wallet's current balance
        uint256 walletBalance = mockERC3009Token.balanceOf(address(smartWalletDeployed));

        // Assume reasonable values
        vm.assume(walletBalance >= maxAmount && maxAmount >= amount && amount > 0);

        // Create payment details with SpendPermission auth type
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentEscrowAuthorization({
            payer: address(smartWalletDeployed),
            maxAmount: maxAmount,
            token: address(mockERC3009Token)
        });

        // Create and sign the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);

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
        paymentEscrow.authorize(paymentInfo, amount, hooks[TokenCollector.SpendPermission], abi.encode(signature, "")); // Empty collectorData for regular spend

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
