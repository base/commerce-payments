// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";

contract PaymentEscrowSmartWalletE2ETest is PaymentEscrowSmartWalletBase {
    function test_charge_succeeds_withDeployedSmartWallet(uint120 amount) public {
        // Get wallet's current balance
        uint256 walletBalance = mockERC3009Token.balanceOf(address(smartWalletDeployed));

        // Assume reasonable values
        vm.assume(amount > 0 && amount <= walletBalance);

        // Create payment info
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization(address(smartWalletDeployed), amount);

        // bytes32 nonce = paymentEscrow.getHash(paymentInfo); // Use paymentInfoHash as nonce

        // Create signature
        bytes memory signature = _signSmartWalletERC3009(paymentInfo, DEPLOYED_WALLET_OWNER_PK, 0);

        // Submit charge
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );

        uint256 feeAmount = amount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(receiver), amount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
    }

    function test_charge_succeeds_withCounterfactualSmartWallet(uint120 amount) public {
        // Get wallet's current balance
        uint256 walletBalance = mockERC3009Token.balanceOf(address(smartWalletCounterfactual));

        // Assume reasonable values
        vm.assume(amount > 0 && amount <= walletBalance);

        // Verify smart wallet is not deployed yet
        address wallet = address(smartWalletCounterfactual);
        assertEq(wallet.code.length, 0, "Smart wallet should not be deployed yet");

        // Create payment details
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentEscrowAuthorization(address(smartWalletCounterfactual), amount);

        // Create signature
        bytes memory signature = _signSmartWalletERC3009WithERC6492(paymentInfo, COUNTERFACTUAL_WALLET_OWNER_PK, 0);

        // Submit charge
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo,
            amount,
            address(erc3009PaymentCollector),
            signature,
            paymentInfo.minFeeBps,
            paymentInfo.feeReceiver
        );

        uint256 feeAmount = amount * FEE_BPS / 10_000;
        assertEq(mockERC3009Token.balanceOf(receiver), amount - feeAmount);
        assertEq(mockERC3009Token.balanceOf(feeReceiver), feeAmount);
    }
}
