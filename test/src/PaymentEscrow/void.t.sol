// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";

import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract AuthorizationVoidedTest is PaymentEscrowBase {
    function test_void_reverts_whenNotOperator() public {
        uint120 authorizedAmount = 100e9;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, randomAddress, paymentInfo.operator)
        );
        paymentEscrow.void(paymentInfo);
    }

    function test_void_revert_noAuthorization(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, paymentInfoHash));
        paymentEscrow.void(paymentInfo);
    }

    function test_void_succeeds_withEscrowedFunds(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = paymentEscrow.getTokenStore(operator);
        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 tokenStoreBalanceBefore = mockERC3009Token.balanceOf(operatorTokenStore);

        // Then void the authorization
        vm.prank(operator);
        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentVoided(paymentInfoHash, paymentInfo, authorizedAmount);
        paymentEscrow.void(paymentInfo);

        // Verify funds were returned to payer
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + authorizedAmount);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), tokenStoreBalanceBefore - authorizedAmount);
    }

    function test_void_emitsCorrectEvents() public {
        uint120 authorizedAmount = 100e9;

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Record all expected events in order
        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentVoided(paymentInfoHash, paymentInfo, authorizedAmount);

        // Then void the authorization and verify events
        vm.prank(operator);
        paymentEscrow.void(paymentInfo);
    }
}
