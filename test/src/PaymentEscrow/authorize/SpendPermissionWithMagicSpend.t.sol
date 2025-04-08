// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

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
            _createPaymentEscrowAuthorization(address(smartWalletDeployed), amount, address(mockERC3009Token));

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
            hooks[TokenCollector.SpendPermission],
            abi.encode(signature, abi.encode(withdrawRequest))
        );

        // Get treasury address after creation
        address operatorTreasury = paymentEscrow.operatorTreasury(operator);

        // Verify balances - funds should move from MagicSpend to escrow
        assertEq(
            mockERC3009Token.balanceOf(address(magicSpend)),
            magicSpendBalanceBefore - amount,
            "MagicSpend balance should decrease by amount"
        );
        assertEq(mockERC3009Token.balanceOf(operatorTreasury), amount, "Treasury balance should increase by amount");
    }
}
