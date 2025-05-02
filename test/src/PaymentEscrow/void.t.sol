// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "../../../src/AuthCaptureEscrow.sol";

import {AuthCaptureEscrowBase} from "../../base/AuthCaptureEscrowBase.sol";

contract AuthorizationVoidedTest is AuthCaptureEscrowBase {
    function test_void_reverts_whenNotOperator() public {
        uint120 authorizedAmount = 100e9;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(AuthCaptureEscrow.InvalidSender.selector, randomAddress, paymentInfo.operator)
        );
        authCaptureEscrow.void(paymentInfo);
    }

    function test_void_revert_noAuthorization(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(AuthCaptureEscrow.ZeroAuthorization.selector, paymentInfoHash));
        authCaptureEscrow.void(paymentInfo);
    }

    function test_void_succeeds_withEscrowedFunds(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        address operatorTokenStore = authCaptureEscrow.getTokenStore(operator);
        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 tokenStoreBalanceBefore = mockERC3009Token.balanceOf(operatorTokenStore);

        // Then void the authorization
        vm.prank(operator);
        vm.expectEmit(true, false, false, false);
        emit AuthCaptureEscrow.PaymentVoided(paymentInfoHash, authorizedAmount);
        authCaptureEscrow.void(paymentInfo);

        // Verify funds were returned to payer
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + authorizedAmount);
        assertEq(mockERC3009Token.balanceOf(operatorTokenStore), tokenStoreBalanceBefore - authorizedAmount);
    }

    function test_void_emitsCorrectEvents() public {
        uint120 authorizedAmount = 100e9;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, authorizedAmount);

        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);

        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        authCaptureEscrow.authorize(paymentInfo, authorizedAmount, address(erc3009PaymentCollector), signature);

        // Record all expected events in order
        vm.expectEmit(true, false, false, false);
        emit AuthCaptureEscrow.PaymentVoided(paymentInfoHash, authorizedAmount);

        // Then void the authorization and verify events
        vm.prank(operator);
        authCaptureEscrow.void(paymentInfo);
    }
}
