// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PreApprovalTokenCollector} from "../../../../src/token-collectorsPreApprovalTokenCollector.sol";
import {ERC20UnsafeTransferTokenCollector} from "../../../../test/mocks/ERC20UnsafeTransferTokenCollector.sol";

contract AuthorizeWithERC20ApprovalTest is PaymentEscrowSmartWalletBase {
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

        // Try to authorize without pre-approval
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalTokenCollector.PaymentNotApproved.selector, paymentDetailsHash)
        );
        paymentEscrow.authorize(amount, paymentDetails, "", "");
    }

    function test_reverts_tokenIsPreApprovedButFundsAreNotTransferred(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, amount, address(mockERC3009Token), TokenCollector.ERC20);
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);

        // Give payer tokens but DON'T approve escrow
        mockERC3009Token.mint(payerEOA, amount);

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.authorize(amount, paymentDetails, "", "");
    }

    function test_reverts_ifHookDoesNotTransferCorrectAmount(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization(
            payerEOA, amount, address(mockERC20Token), TokenCollector.ERC20UnsafeTransfer
        );

        // approve hook to transfer tokens
        vm.prank(payerEOA);
        mockERC20Token.approve(address(hooks[TokenCollector.ERC20UnsafeTransfer]), amount);

        // Pre-approve in hook
        vm.prank(payerEOA);
        ERC20UnsafeTransferTokenCollector(address(hooks[TokenCollector.ERC20UnsafeTransfer])).preApprove(paymentDetails);

        // mint tokens to buyer
        mockERC20Token.mint(payerEOA, amount);

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.TokenPullFailed.selector));
        paymentEscrow.authorize(amount, paymentDetails, "", "");
    }

    function test_succeeds_ifTokenIsPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, amount, address(mockERC3009Token), TokenCollector.ERC20);
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalTokenCollector(address(hooks[TokenCollector.ERC20])).preApprove(paymentDetails);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(hooks[TokenCollector.ERC20]), amount);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Authorize with ERC20Approval method
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, "", "");

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), escrowBalanceBefore + amount);
    }
}
