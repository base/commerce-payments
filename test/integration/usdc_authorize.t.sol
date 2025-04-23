// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {PaymentEscrowForkBase} from "./PaymentEscrowForkBase.sol";

contract USDCAuthorizeForkTest is PaymentEscrowForkBase {
    function test_USDCAuthorize(uint120 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= MAX_AMOUNT);

        // Fund payerEOA with USDC
        _fundWithUSDC(payerEOA, amount);

        // Create payment info
        PaymentEscrow.PaymentInfo memory paymentInfo = createPaymentInfo(payerEOA, amount);

        // Sign the authorization
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // Record balances before
        uint256 payerBalanceBefore = usdc.balanceOf(payerEOA);

        // Submit authorization
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Get token store address after creation
        address operatorTokenStore = paymentEscrow.getTokenStore(operator);

        // Verify balances
        assertEq(usdc.balanceOf(payerEOA), payerBalanceBefore - amount, "Payer balance should decrease by amount");
        assertEq(usdc.balanceOf(operatorTokenStore), amount, "Token store balance should increase by amount");
    }
}
