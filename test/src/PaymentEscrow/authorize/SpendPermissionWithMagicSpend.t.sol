// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magic-spend/MagicSpend.sol";

contract AuthorizeWithSpendPermissionWithMagicSpendTest is PaymentEscrowSmartWalletBase {
    function test_succeeds_withMagicSpendWithdraw(uint256 amount) public {
        // Assume reasonable values and fund MagicSpend
        vm.assume(amount > 0 && amount <= type(uint120).max);
        mockERC3009Token.mint(address(magicSpend), amount);

        // Create payment details with SpendPermissionWithMagicSpend auth type
        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(
            address(smartWalletDeployed), amount, address(mockERC3009Token), TokenCollector.SpendPermission
        );

        // Create the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentDetails);

        // Create and sign withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission);
        withdrawRequest.asset = address(mockERC3009Token);
        withdrawRequest.amount = amount;
        withdrawRequest.signature = _signWithdrawRequest(address(smartWalletDeployed), withdrawRequest);

        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        // Record balances before
        uint256 magicSpendBalanceBefore = mockERC3009Token.balanceOf(address(magicSpend));
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Submit authorization
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature, abi.encode(withdrawRequest));

        // Verify balances - funds should move from MagicSpend to escrow
        assertEq(
            mockERC3009Token.balanceOf(address(magicSpend)),
            magicSpendBalanceBefore - amount,
            "MagicSpend balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(address(paymentEscrow)),
            escrowBalanceBefore + amount,
            "Escrow balance should increase by amount"
        );
    }
}
