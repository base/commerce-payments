// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {MockBlocklistToken} from "../../mocks/MockBlocklistToken.sol";

contract DisburseFeesToFeeReceiverTest is PaymentEscrowBase {
    function test_succeeds_whenFeeStoreHasBalance(uint120 authorizedAmount, uint16 feeBps, address feeReceiver)
        public
    {
        vm.assume(authorizedAmount > 0);
        vm.assume(feeBps > 0 && feeBps <= 10_000);
        vm.assume(feeReceiver != address(0));
        vm.assume(feeReceiver != operator);
        vm.assume(feeReceiver != receiver);
        vm.assume(feeReceiver != payerEOA);

        // Create payment info with blocklist token
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: authorizedAmount, token: address(mockBlocklistToken)});
        paymentInfo.minFeeBps = feeBps;
        paymentInfo.maxFeeBps = feeBps;
        paymentInfo.feeReceiver = feeReceiver;

        mockBlocklistToken.mint(payerEOA, authorizedAmount);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Block the fee receiver
        mockBlocklistToken.block(feeReceiver);

        // Calculate expected fee amount
        uint256 feeAmount = (uint256(authorizedAmount) * uint256(feeBps)) / 10_000;
        uint256 receiverAmount = uint256(authorizedAmount) - feeAmount;

        // Capture payment - fee transfer should fail but be stored in fee store
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, authorizedAmount, feeBps, feeReceiver);

        address feeStore = paymentEscrow.getFeeStore(feeReceiver);

        // Verify balances before disbursement
        assertEq(mockBlocklistToken.balanceOf(receiver), receiverAmount);
        assertEq(mockBlocklistToken.balanceOf(feeReceiver), 0);
        assertEq(mockBlocklistToken.balanceOf(feeStore), feeAmount);

        // Unblock fee receiver and disburse fees
        mockBlocklistToken.unblock(feeReceiver);
        vm.prank(operator);
        paymentEscrow.disburseFeesToFeeReceiver(feeReceiver, address(mockBlocklistToken));

        // Verify fees were disbursed
        assertEq(mockBlocklistToken.balanceOf(feeReceiver), feeAmount);
        assertEq(mockBlocklistToken.balanceOf(feeStore), 0);
    }

    function test_succeeds_whenFeeStoreEmpty(uint120 authorizedAmount, uint16 feeBps, address feeReceiver) public {
        vm.assume(authorizedAmount > 0);
        vm.assume(feeBps > 0 && feeBps <= 10_000);
        vm.assume(feeReceiver != address(0));
        vm.assume(feeReceiver != operator);
        vm.assume(feeReceiver != receiver);
        vm.assume(feeReceiver != payerEOA);

        // Create payment info with blocklist token
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: authorizedAmount, token: address(mockBlocklistToken)});
        paymentInfo.minFeeBps = feeBps;
        paymentInfo.maxFeeBps = feeBps;
        paymentInfo.feeReceiver = feeReceiver;

        // Mint tokens to payer
        mockBlocklistToken.mint(payerEOA, authorizedAmount);

        // Authorize payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Block the fee receiver
        mockBlocklistToken.block(feeReceiver);

        // Calculate expected fee amount
        uint256 feeAmount = (uint256(authorizedAmount) * uint256(feeBps)) / 10_000;
        uint256 receiverAmount = uint256(authorizedAmount) - feeAmount;

        // Capture payment - fee transfer should fail but be stored in fee store
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, authorizedAmount, feeBps, feeReceiver);

        address feeStore = paymentEscrow.getFeeStore(feeReceiver);

        // Verify balances before disbursement
        assertEq(mockBlocklistToken.balanceOf(receiver), receiverAmount);
        assertEq(mockBlocklistToken.balanceOf(feeReceiver), 0);
        assertEq(mockBlocklistToken.balanceOf(feeStore), feeAmount);

        // Unblock fee receiver and disburse fees
        mockBlocklistToken.unblock(feeReceiver);
        vm.prank(operator);
        paymentEscrow.disburseFeesToFeeReceiver(feeReceiver, address(mockBlocklistToken));

        // Verify fees were disbursed
        assertEq(mockBlocklistToken.balanceOf(feeReceiver), feeAmount);
        assertEq(mockBlocklistToken.balanceOf(feeStore), 0);

        // Try to disburse again - should succeed but do nothing
        vm.prank(operator);
        paymentEscrow.disburseFeesToFeeReceiver(feeReceiver, address(mockBlocklistToken));

        // Verify balances remain unchanged
        assertEq(mockBlocklistToken.balanceOf(feeReceiver), feeAmount);
        assertEq(mockBlocklistToken.balanceOf(feeStore), 0);
    }

    function test_succeeds_whenFeeStoreNotDeployed(address feeReceiver, address token) public {
        vm.assume(feeReceiver != address(0));
        vm.assume(token != address(0));

        // Get fee store address
        address feeStore = paymentEscrow.getFeeStore(feeReceiver);
        assertEq(feeStore.code.length, 0, "Fee store should not be deployed");

        // Try to disburse fees - should succeed but do nothing
        vm.prank(operator);
        paymentEscrow.disburseFeesToFeeReceiver(feeReceiver, token);

        // Verify fee store is still not deployed
        assertEq(feeStore.code.length, 0, "Fee store should still not be deployed");
    }
}
