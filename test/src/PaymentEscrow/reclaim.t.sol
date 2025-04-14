// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract ReclaimTest is PaymentEscrowBase {
    function test_reverts_ifSenderIsNotpayer(address invalidSender, uint120 amount) public {
        vm.assume(invalidSender != payerEOA);
        vm.assume(invalidSender != address(0));
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Try to reclaim with invalid sender
        vm.warp(paymentInfo.authorizationExpiry);
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender, paymentInfo.payer));
        paymentEscrow.reclaim(paymentInfo);
    }

    function test_reverts_ifBeforeAuthorizationExpiry(uint120 amount, uint48 currentTime) public {
        vm.assume(amount > 0);

        uint48 authorizationExpiry = uint48(block.timestamp + 1 days);
        vm.assume(currentTime < authorizationExpiry);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        // Set both deadlines - ensure preApprovalExpiry is before authorizationExpiry
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.preApprovalExpiry = authorizationExpiry - 1 hours; // Set authorize deadline before capture deadline

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Try to reclaim before deadline
        vm.warp(currentTime);
        vm.prank(payerEOA);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.BeforeAuthorizationExpiry.selector, currentTime, authorizationExpiry)
        );
        paymentEscrow.reclaim(paymentInfo);
    }

    function test_reverts_ifAuthorizedValueIsZero(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // Try to reclaim without any authorization
        vm.warp(paymentInfo.authorizationExpiry);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, paymentEscrow.getHash(paymentInfo))
        );
        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);
    }

    function test_reverts_ifAlreadyReclaimed(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Reclaim the payment the first time
        vm.warp(paymentInfo.authorizationExpiry);
        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);

        // Try to reclaim again
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, paymentEscrow.getHash(paymentInfo))
        );
        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);
    }

    function test_succeeds_ifCalledByPayerAfterAuthorizationExpiry(uint120 amount, uint48 timeAfterDeadline) public {
        vm.assume(amount > 0);

        uint48 authorizationExpiry = uint48(block.timestamp + 1 days);
        vm.assume(timeAfterDeadline > authorizationExpiry);
        vm.assume(timeAfterDeadline < type(uint48).max);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});
        // Set both deadlines - ensure preApprovalExpiry is before authorizationExpiry
        paymentInfo.authorizationExpiry = authorizationExpiry;
        paymentInfo.preApprovalExpiry = authorizationExpiry - 1 hours; // Set authorize deadline before capture deadline

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = paymentEscrow.getTokenStore(operator);
        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 operatorTokenStoreBalanceBefore = mockERC3009Token.balanceOf(operatorTokenStore);

        // Reclaim after deadline
        vm.warp(timeAfterDeadline);
        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);

        // Verify balances
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + amount);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), operatorTokenStoreBalanceBefore - amount);
    }

    function test_emitsExpectedEvents(uint120 amount) public {
        vm.assume(amount > 0);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo({payer: payerEOA, maxAmount: amount});

        // First authorize the payment
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, amount);

        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, amount, address(erc3009PaymentCollector), signature);

        // Prepare for reclaim
        vm.warp(paymentInfo.authorizationExpiry);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentReclaimed(paymentInfoHash, amount);

        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);
    }
}
