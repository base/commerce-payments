// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";

contract SpendPermissionPaymentCollectorTest is PaymentEscrowSmartWalletBase {
    function test_collectTokens_reverts_whenCalledByNonPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        spendPermissionPaymentCollector.collectTokens(paymentInfo, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(address(smartWalletDeployed), amount);
        // Create payment info with SpendPermission auth type
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({
            payer: address(smartWalletDeployed),
            maxAmount: amount,
            token: address(mockERC3009Token)
        });

        // Create and sign the spend permission
        SpendPermissionManager.SpendPermission memory permission = _createSpendPermission(paymentInfo);

        bytes memory signature = _signSpendPermission(
            permission,
            DEPLOYED_WALLET_OWNER_PK,
            0 // owner index
        );

        vm.prank(address(paymentEscrow));
        spendPermissionPaymentCollector.collectTokens(paymentInfo, amount, abi.encode(signature, ""));
    }
}
