// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SpendPermissionManager} from "spend-permissions/SpendPermissionManager.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {PaymentEscrowForkBase} from "../base/PaymentEscrowForkBase.sol";

contract USDCForkTest is PaymentEscrowForkBase {
    function test_pay_withEOA_ERC3009(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        _fundWithUSDC(payerEOA, amount);

        PaymentEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(payerEOA, amount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        uint256 payerBalanceBefore = usdc.balanceOf(payerEOA);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = paymentEscrow.getTokenStore(operator);

        assertEq(usdc.balanceOf(payerEOA), payerBalanceBefore - amount, "Payer balance should decrease by amount");
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }

    function test_authorize_withCoinbaseSmartWallet_ERC3009(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        _fundWithUSDC(address(smartWalletDeployed), amount);

        PaymentEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(address(smartWalletDeployed), amount);

        bytes memory signature = _signSmartWalletERC3009(paymentInfo, DEPLOYED_WALLET_OWNER_PK, 0);

        uint256 payerBalanceBefore = usdc.balanceOf(address(smartWalletDeployed));

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = paymentEscrow.getTokenStore(operator);

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

        PaymentEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(address(smartWalletDeployed), amount);
        SpendPermissionManager.SpendPermission memory spendPermission = _createSpendPermission(paymentInfo);

        bytes memory signature = _signSpendPermission(spendPermission, DEPLOYED_WALLET_OWNER_PK, 0);

        uint256 payerBalanceBefore = usdc.balanceOf(address(smartWalletDeployed));

        // Encode the collector data as a tuple of (bytes, bytes)
        bytes memory collectorData = abi.encode(signature, "");

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(spendPermissionPaymentCollector), collectorData);

        address operatorTokenStore = paymentEscrow.getTokenStore(operator);

        assertEq(
            usdc.balanceOf(address(smartWalletDeployed)),
            payerBalanceBefore - amount,
            "Payer balance should decrease by amount"
        );
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }
}
