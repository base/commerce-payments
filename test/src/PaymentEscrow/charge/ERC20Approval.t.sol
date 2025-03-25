// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract ChargeWithERC20ApprovalTest is PaymentEscrowBase {
    function test_reverts_tokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        // Give buyer tokens and approve escrow
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to charge without pre-approval in Escrow contract
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.PaymentNotApproved.selector, keccak256(abi.encode(paymentDetails)))
        );
        paymentEscrow.charge(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient, "");
    }

    function test_reverts_tokenIsPreApprovedButFundsAreNotTransferred(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        // Pre-approve in escrow
        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Give buyer tokens but DON'T approve escrow
        mockERC3009Token.mint(buyerEOA, amount);

        // Try to charge - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.charge(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient, "");
    }

    function test_succeeds_ifTokenIsPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            buyer: buyerEOA,
            value: amount,
            token: address(mockERC3009Token),
            authType: PaymentEscrow.AuthorizationType.ERC20Approval
        });

        // Pre-approve in escrow
        vm.prank(buyerEOA);
        paymentEscrow.preApprove(paymentDetails);

        // Give buyer tokens and approve escrow
        mockERC3009Token.mint(buyerEOA, amount);
        vm.prank(buyerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 captureAddressBalanceBefore = mockERC3009Token.balanceOf(captureAddress);
        uint256 feeRecipientBalanceBefore = mockERC3009Token.balanceOf(feeRecipient);

        // Charge with empty signature
        vm.prank(operator);
        paymentEscrow.charge(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient, "");

        // Verify balances including fee distribution
        uint256 feeAmount = uint256(amount) * paymentDetails.minFeeBps / 10_000;
        assertEq(mockERC3009Token.balanceOf(captureAddress), captureAddressBalanceBefore + (amount - feeAmount));
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeRecipientBalanceBefore + feeAmount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
    }
}
