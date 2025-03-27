// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

contract AuthorizeWithPermit2Test is PaymentEscrowSmartWalletBase {
    // Non-ERC3009 token to guarantee no false positive use of Permit2 path
    MockERC20 public plainToken;

    function setUp() public override {
        // Initialize PaymentEscrow with Permit2 first
        super.setUp();

        // Deploy a regular ERC20 without ERC3009
        plainToken = new MockERC20("Plain Token", "PLAIN", 18);

        // payer needs to approve Permit2 to spend their tokens
        vm.startPrank(payerEOA);
        plainToken.approve(permit2, type(uint256).max);
        vm.stopPrank();
    }

    function test_permit2_succeeds_whenValueEqualsAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        // Mint enough tokens to the payer
        plainToken.mint(payerEOA, amount);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: amount,
            token: address(plainToken),
            hook: PullTokensHook.Permit2
        });

        // Generate Permit2 signature using the same deadline as paymentDetails
        bytes memory signature = _signPermit2Transfer({
            token: address(plainToken),
            amount: amount,
            deadline: paymentDetails.preApprovalExpiry,
            nonce: uint256(keccak256(abi.encode(paymentDetails))),
            privateKey: payer_EOA_PK
        });

        // Should succeed via Permit2 authorization
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature, "");

        // Verify the transfer worked
        assertEq(plainToken.balanceOf(address(paymentEscrow)), amount);
        assertEq(plainToken.balanceOf(payerEOA), 0);
    }
}
