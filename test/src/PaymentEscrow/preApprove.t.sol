// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {ERC20PullTokensHook} from "../../../src/hooks/ERC20PullTokensHook.sol";

contract PreApproveTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotpayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);
    }

    function test_reverts_ifPaymentIsAlreadyAuthorized(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        // First authorize the payment
        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature, "");
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        // Now try to pre-approve
        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20PullTokensHook.PaymentAlreadyAuthorized.selector, paymentDetailsHash)
        );
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);
    }

    function test_succeeds_ifCalledBypayer(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: amount,
            token: address(mockERC3009Token),
            hook: PullTokensHook.ERC20
        });
        vm.prank(payerEOA);
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);

        // Verify state change by trying to authorize with empty signature
        mockERC3009Token.mint(payerEOA, amount);
        vm.startPrank(payerEOA);
        mockERC3009Token.approve(address(hooks[PullTokensHook.ERC20]), amount);
        vm.stopPrank();

        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, "", ""); // ERC20Approval should work after pre-approval
    }

    function test_reverts_ifCalledBypayerMultipleTimes(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails = _createPaymentEscrowAuthorization({
            payer: payerEOA,
            value: amount,
            token: address(mockERC3009Token),
            hook: PullTokensHook.ERC20
        });

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.startPrank(payerEOA);
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20PullTokensHook.PaymentAlreadyPreApproved.selector, paymentDetailsHash)
        );
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({payer: payerEOA, value: amount});

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.expectEmit(true, false, false, false);
        emit ERC20PullTokensHook.PaymentApproved(paymentDetailsHash);

        vm.prank(payerEOA);
        ERC20PullTokensHook(address(hooks[PullTokensHook.ERC20])).preApprove(paymentDetails);
    }
}
