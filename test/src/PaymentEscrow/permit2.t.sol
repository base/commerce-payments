// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {Test, console} from "forge-std/Test.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";

contract Permit2Test is PaymentEscrowBase {
    // Non-ERC3009 token to guarantee no false positive use of Permit2 path
    MockERC20 public plainToken;

    function setUp() public override {
        // Initialize PaymentEscrow with Permit2 first
        super.setUp();

        // Deploy a regular ERC20 without ERC3009
        plainToken = new MockERC20("Plain Token", "PLAIN", 18);

        // Mint some tokens to the buyer
        plainToken.mint(buyerEOA, 1000e18);

        // Buyer needs to approve Permit2 to spend their tokens
        vm.startPrank(buyerEOA);
        plainToken.approve(address(paymentEscrow.permit2()), type(uint256).max);
        vm.stopPrank();
    }

    function test_authorize_succeeds_withPermit2Fallback() public {
        uint256 amount = 100e18;

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(plainToken),
            authType: PaymentEscrow.AuthorizationType.Permit2
        });

        // Generate Permit2 signature using the same deadline as paymentDetails
        bytes memory signature = _signPermit2Transfer({
            token: address(plainToken),
            amount: amount,
            deadline: paymentDetails.authorizeDeadline,
            nonce: uint256(keccak256(abi.encode(paymentDetails))),
            privateKey: BUYER_EOA_PK
        });

        // Should succeed via Permit2 fallback
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Verify the transfer worked
        assertEq(plainToken.balanceOf(address(paymentEscrow)), amount);
        assertEq(plainToken.balanceOf(buyerEOA), 900e18);
    }
}
