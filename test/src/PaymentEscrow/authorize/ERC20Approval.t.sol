// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrowSmartWalletBase} from "../../../base/PaymentEscrowSmartWalletBase.sol";
import {PaymentEscrow} from "../../../../src/PaymentEscrow.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PreApprovalPaymentCollector} from "../../../../src/collectors/PreApprovalPaymentCollector.sol";
import {ERC20UnsafeTransferTokenCollector} from "../../../../test/mocks/ERC20UnsafeTransferTokenCollector.sol";

contract AuthorizeWithERC20ApprovalTest is PaymentEscrowSmartWalletBase {
    function test_reverts_tokenIsNotPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockERC3009Token)});
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(paymentEscrow), amount);

        // Try to authorize without pre-approval
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PreApprovalPaymentCollector.PaymentNotPreApproved.selector, paymentInfoHash)
        );
        paymentEscrow.authorize(paymentInfo, amount, address(preApprovalPaymentCollector), "");
    }

    function test_reverts_tokenIsPreApprovedButFundsAreNotTransferred(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount, address(mockERC3009Token));
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);

        // Give payer tokens but DON'T approve escrow
        mockERC3009Token.mint(payerEOA, amount);

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.TransferFromFailed.selector));
        paymentEscrow.authorize(paymentInfo, amount, address(preApprovalPaymentCollector), "");
    }

    function test_reverts_ifHookDoesNotTransferCorrectAmount(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount, address(mockERC20Token));

        // approve hook to transfer tokens
        vm.prank(payerEOA);
        mockERC20Token.approve(address(erc20UnsafeTransferPaymentCollector), amount);

        // Pre-approve in hook
        vm.prank(payerEOA);
        ERC20UnsafeTransferTokenCollector(address(erc20UnsafeTransferPaymentCollector)).preApprove(paymentInfo);

        // mint tokens to buyer
        mockERC20Token.mint(payerEOA, amount);

        // Try to authorize - should fail on token transfer
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.TokenCollectionFailed.selector));
        paymentEscrow.authorize(paymentInfo, amount, address(erc20UnsafeTransferPaymentCollector), "");
    }

    function test_succeeds_ifTokenIsPreApproved(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount, address(mockERC3009Token));
        // Pre-approve in escrow
        vm.prank(payerEOA);
        PreApprovalPaymentCollector(address(preApprovalPaymentCollector)).preApprove(paymentInfo);

        // Give payer tokens and approve escrow
        mockERC3009Token.mint(payerEOA, amount);
        vm.prank(payerEOA);
        mockERC3009Token.approve(address(preApprovalPaymentCollector), amount);

        // Authorize with ERC20Approval method
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(preApprovalPaymentCollector), "");

        // Verify balances
        address operatorTokenStore = paymentEscrow.getTokenStore(operator);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), amount);
    }
}
