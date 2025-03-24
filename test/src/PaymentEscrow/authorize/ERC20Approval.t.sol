// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AuthorizeWithERC20ApprovalTest is PaymentEscrowSmartWalletBase {
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

        // Try to authorize without pre-approval
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.PaymentNotApproved.selector, keccak256(abi.encode(paymentDetails)))
        );
        paymentEscrow.authorize(amount, paymentDetails, "");
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

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.authorize(amount, paymentDetails, "");
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
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Authorize with ERC20Approval method
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, "");

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + amount);
    }
}
