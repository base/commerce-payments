// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract AuthorizationVoidedTest is PaymentEscrowBase {
    function test_void_reverts_whenNotOperatorOrreceiver() public {
        uint256 authorizedAmount = 100e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        address randomAddress = makeAddr("randomAddress");
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, randomAddress));
        paymentEscrow.void(paymentDetails);
    }

    function test_void_revert_noAuthorization(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ZeroAuthorization.selector, paymentDetailsHash));
        paymentEscrow.void(paymentDetails);
    }

    function test_void_succeeds_withEscrowedFunds(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, hooks[TokenCollector.ERC3009], signature);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Then void the authorization
        vm.prank(operator);
        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentVoided(paymentDetailsHash, authorizedAmount, address(this));
        paymentEscrow.void(paymentDetails);

        // Verify funds were returned to payer
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + escrowBalanceBefore);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_void_succeeds_whenCalledByreceiver(uint120 authorizedAmount) public {
        uint256 payerBalance = mockERC3009Token.balanceOf(payerEOA);

        vm.assume(authorizedAmount > 0 && authorizedAmount <= payerBalance);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, hooks[TokenCollector.ERC3009], signature);

        uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
        uint256 escrowBalanceBefore = mockERC3009Token.balanceOf(address(paymentEscrow));

        // Then void the authorization as receiver
        vm.prank(receiver);
        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentVoided(paymentDetailsHash, authorizedAmount, address(this));
        paymentEscrow.void(paymentDetails);

        // Verify funds were returned to payer
        assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + escrowBalanceBefore);
        assertEq(mockERC3009Token.balanceOf(address(paymentEscrow)), 0);
    }

    function test_void_emitsCorrectEvents() public {
        uint256 authorizedAmount = 100e6;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization(payerEOA, authorizedAmount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

        // First confirm the authorization to escrow funds
        vm.prank(operator);
        paymentEscrow.authorize(authorizedAmount, paymentDetails, hooks[TokenCollector.ERC3009], signature);

        // Record all expected events in order
        vm.expectEmit(true, false, false, false);
        emit PaymentEscrow.PaymentVoided(paymentDetailsHash, authorizedAmount, address(this));

        // Then void the authorization and verify events
        vm.prank(operator);
        paymentEscrow.void(paymentDetails);
    }
}
