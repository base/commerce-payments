// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";
import {ReentrantTokenCollector} from "../../../test/mocks/ReentrantTokenCollector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract ReentrancyApproveTest is PaymentEscrowSmartWalletBase {
    ReentrantTokenCollector reentrantTokenCollector;
    address attacker;
    uint256 attackerPrivateKey;

    function setUp() public override {
        super.setUp();
        reentrantTokenCollector = new ReentrantTokenCollector(address(paymentEscrow));
        attackerPrivateKey = 0x123;
        attacker = vm.addr(attackerPrivateKey);
        // label the attacker and evil collector as evil
        vm.label(attacker, "ATTACKER");
        vm.label(address(reentrantTokenCollector), "REENTRANT COLLECTOR");
    }

    function test_reentrancy() public {
        uint120 amount = 10 ether;
        mockERC3009Token.mint(address(paymentEscrow), amount); // give escrow liquidity
        mockERC3009Token.mint(address(reentrantTokenCollector), amount); // give evil collector enough liquidity for attack
        vm.prank(address(reentrantTokenCollector));
        mockERC3009Token.approve(address(paymentEscrow), amount); // allow paymentEscrow to transfer tokens from collector
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

        console.log("Initial Attacker Balance:     ", mockERC3009Token.balanceOf(attacker));
        vm.prank(attacker);
        paymentEscrow.authorize(paymentInfo, 10 ether, address(reentrantTokenCollector), "");

        vm.startPrank(attacker);
        paymentEscrow.capture(paymentInfo, 10 ether, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        paymentInfo.salt += 1; // set up the second unique paymentInfo
        vm.expectRevert(); // expect revert because we've fixed the reentrancy
        paymentEscrow.capture(paymentInfo, 10 ether, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();

        console.log("After attack Attacker Balance:", mockERC3009Token.balanceOf(attacker));
        console.log("Final Escrow Balance:       ", mockERC3009Token.balanceOf(address(paymentEscrow)));
    }
}
