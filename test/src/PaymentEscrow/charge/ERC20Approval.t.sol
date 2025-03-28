// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../../base/PaymentEscrowBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PreApprovalTokenCollector} from "../../../../src/token-collectorsPreApprovalTokenCollector.sol";

contract ChargeWithERC20ApprovalTest is PaymentEscrowBase {
    function test_reverts_tokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            maxAmount: amount,
            token: address(mockERC3009Token),
            hook: TokenCollector.ERC20
        });
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to charge without pre-approval in Escrow contract
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalTokenCollector.PaymentNotApproved.selector, paymentDetailsHash)
        );
        paymentEscrow.charge(amount, paymentDetails, "", "", paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_reverts_tokenIsPreApprovedButFundsAreNotTransferred(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            maxAmount: amount,
            token: address(mockERC3009Token),
            hook: TokenCollector.ERC20
        });
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);

        // Give payer tokens but DON'T approve escrow
        mockERC3009Token.mint(payerEOA, amount);

        // Try to charge - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.charge(amount, paymentDetails, "", "", paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    }

    function test_succeeds_ifTokenIsPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            maxAmount: amount,
            token: address(mockERC3009Token),
            hook: TokenCollector.ERC20
        });
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(hooks[TokenCollector.ERC20]), amount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 receiverBalanceBefore = mockERC3009Token.balanceOf(receiver);
        uint256 feeRecipientBalanceBefore = mockERC3009Token.balanceOf(feeRecipient);

        // Charge with empty signature
        vm.prank(operator);
        paymentEscrow.charge(amount, paymentDetails, "", "", paymentDetails.minFeeBps, paymentDetails.feeRecipient);

        // Verify balances including fee distribution
        uint256 feeAmount = uint256(amount) * paymentDetails.minFeeBps / 10_000;
        assertEq(mockERC3009Token.balanceOf(receiver), receiverBalanceBefore + (amount - feeAmount));
        assertEq(mockERC3009Token.balanceOf(feeRecipient), feeRecipientBalanceBefore + feeAmount);
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
    }
}
