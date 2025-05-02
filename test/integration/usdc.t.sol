// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {AuthCaptureEscrow} from "../../src/AuthCaptureEscrow.sol";
import {AuthCaptureEscrowForkBase} from "../base/AuthCaptureEscrowForkBase.sol";

contract USDCForkTest is AuthCaptureEscrowForkBase {
    function test_pay_withEOA_ERC3009(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        _fundWithUSDC(payerEOA, amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: payerEOA,
            receiver: receiver,
            token: address(usdc),
            maxAmount: amount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: 0
        });

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = usdc.balanceOf(payerEOA);

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        assertEq(usdc.balanceOf(payerEOA), payerBalanceBefore - amount, "Payer balance should decrease by amount");
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }

    function test_authorize_withCoinbaseSmartWallet_ERC3009(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        _fundWithUSDC(address(smartWalletDeployed), amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: address(smartWalletDeployed),
            receiver: receiver,
            token: address(usdc),
            maxAmount: amount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: 0
        });

        bytes memory signature = _signSmartWalletERC3009(paymentInfo, DEPLOYED_WALLET_OWNER_PK, 0);

        uint256 payerBalanceBefore = usdc.balanceOf(address(smartWalletDeployed));

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        assertEq(
            usdc.balanceOf(address(smartWalletDeployed)),
            payerBalanceBefore - amount,
            "Payer balance should decrease by amount"
        );
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }

    function test_authorize_withCoinbaseSmartWallet_spendPermissions(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        _fundWithUSDC(address(smartWalletDeployed), amount);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: address(smartWalletDeployed),
            receiver: receiver,
            token: address(usdc),
            maxAmount: amount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: 0
        });

        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission(paymentInfo);

        bytes memory signature = _signSpendPermission(spendPermission, DEPLOYED_WALLET_OWNER_PK, 0);

        uint256 payerBalanceBefore = usdc.balanceOf(address(smartWalletDeployed));

        // Encode the collector data as a tuple of (bytes, bytes)
        bytes memory collectorData = abi.encode(signature, "");

        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, amount, address(spendPermissionPaymentCollector), collectorData);

        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);

        assertEq(
            usdc.balanceOf(address(smartWalletDeployed)),
            payerBalanceBefore - amount,
            "Payer balance should decrease by amount"
        );
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }
}
