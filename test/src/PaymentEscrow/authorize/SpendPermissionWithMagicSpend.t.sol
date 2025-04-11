// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {MagicSpend} from "magicspend/MagicSpend.sol";

contract AuthorizeWithSpendPermissionWithMagicSpendTest is PaymentEscrowSmartWalletBase {
    function test_succeeds_withMagicSpendWithdraw(uint120 amount) public {
        // Assume reasonable values and fund MagicSpend
        vm.assume(amount > 0);
        mockERC3009Token.mint(address(magicSpend), amount);

        // Create payment info with SpendPermissionWithMagicSpend auth type
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(smartWalletDeployed), amount, address(mockERC3009Token));

        // Create the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);

        // Create and sign withdraw request
        MagicSpend.WithdrawRequest memory withdrawRequest = _createWithdrawRequest(permission);
        withdrawRequest.asset = address(mockERC3009Token);
        withdrawRequest.amount = amount;
        withdrawRequest.signature = _signWithdrawRequest(address(smartWalletDeployed), withdrawRequest);

        bytes memory signature = _signSpendPermission(permission, DEPLOYED_WALLET_OWNER_PK, 0);

        // Record balances before
        uint256 magicSpendBalanceBefore = mockERC3009Token.balanceOf(address(magicSpend));

        // Submit authorization
        vm.prank(operator);
        paymentEscrow.authorize(
            paymentInfo,
            amount,
            address(spendPermissionPaymentCollector),
            abi.encode(signature, abi.encode(withdrawRequest))
        );

        // Get token store address after creation
        address operatorTokenStore = paymentEscrow.getOperatorTokenStore(operator);

        // Verify balances - funds should move from MagicSpend to escrow
        assertEq(
            mockERC3009Token.balanceOf(address(magicSpend)),
            magicSpendBalanceBefore - amount,
            "MagicSpend balance should decrease by amount"
        );
        assertEq(
            mockERC3009Token.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount"
        );
    }
}
