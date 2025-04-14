// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";

contract AuthorizeWithSpendPermissionTest is PaymentEscrowSmartWalletBase {
    function test_succeeds_withDeployedSmartWallet(uint120 maxAmount, uint120 amount) public {
        // Get wallet's current balance
        uint256 walletBalance = mockERC3009Token.balanceOf(address(smartWalletDeployed));

        // Assume reasonable values
        vm.assume(walletBalance >= maxAmount && maxAmount >= amount && amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
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

        // Submit authorization
        vm.prank(operator);
        paymentEscrow.authorize(
            paymentInfo, amount, address(spendPermissionPaymentCollector), abi.encode(signature, "")
        ); // Empty collectorData for regular spend

        // Get token store address after creation
        address operatorTokenStore = paymentEscrow.getTokenStore(operator);

        // Verify balances
        assertEq(
            mockERC3009Token.balanceOf(address(smartWalletDeployed)),
            walletBalanceBefore - amount,
            "Wallet balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount"
        );
    }
}
