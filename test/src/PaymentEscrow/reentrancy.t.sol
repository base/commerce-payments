// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "../../../src/collectors/PreApprovalPaymentCollector.sol";

import {AuthCaptureEscrowSmartWalletBase} from "../../base/AuthCaptureEscrowSmartWalletBase.sol";
import {ReentrantTokenCollector} from "../../../test/mocks/ReentrantTokenCollector.sol";

contract ReentrancyApproveTest is AuthCaptureEscrowSmartWalletBase {
    ReentrantTokenCollector reentrantTokenCollector;
    address attacker;
    uint256 attackerPrivateKey;

    function setUp() public override {
        super.setUp();
        reentrantTokenCollector = new ReentrantTokenCollector(address(authCaptureEscrow));
        attackerPrivateKey = 0x123;
        attacker = vm.addr(attackerPrivateKey);
        // label the attacker and evil collector as evil
        vm.label(attacker, "ATTACKER");
        vm.label(address(reentrantTokenCollector), "REENTRANT COLLECTOR");
    }

    function test_reentrancy() public {
        uint120 amount = 10 ether;
        mockERC3009Token.mint(address(authCaptureEscrow), amount); // give escrow liquidity
        mockERC3009Token.mint(address(reentrantTokenCollector), amount); // give evil collector enough liquidity for attack
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
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
        vm.startPrank(attacker);

        // Use low-level call to detect revert
        bytes memory callData = abi.encodeWithSelector(
            AuthCaptureEscrow.authorize.selector, paymentInfo, 10 ether, address(reentrantTokenCollector), ""
        );

        (bool success, bytes memory returnData) = address(authCaptureEscrow).call(callData);
        assertFalse(success, "Reentrancy attack should fail");

        if (!success) {
            console.log("Revert reason:");
            console.logBytes(returnData);
        }

        console.log("After authorize attempt");
        vm.expectRevert(); // expect revert because authorize never happened
        authCaptureEscrow.capture(paymentInfo, 10 ether, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        paymentInfo.salt += 1; // set up the second unique paymentInfo
        vm.expectRevert(); // expect revert because we've fixed the reentrancy
        authCaptureEscrow.capture(paymentInfo, 10 ether, paymentInfo.minFeeBps, paymentInfo.feeReceiver);
        vm.stopPrank();

        console.log("After attack Attacker Balance:", mockERC3009Token.balanceOf(attacker));
        console.log("Final Escrow Balance:       ", mockERC3009Token.balanceOf(address(authCaptureEscrow)));
    }
}
