// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RegisterApprovalTest is PaymentEscrowBase {
    function test_succeeds_whenCalledByBuyer(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash, amount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(amount, paymentDetails);
    }

    function test_reverts_whenCalledByNonBuyer() public {
        uint256 amount = 100e6;
        address nonBuyer = makeAddr("nonBuyer");

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(nonBuyer);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, nonBuyer));
        paymentEscrow.registerApproval(amount, paymentDetails);
    }

    function test_reverts_whenValueExceedsAuthorized(uint256 amount) public {
        uint256 buyerBalance = mockERC3009Token.balanceOf(buyerEOA);
        vm.assume(amount > 0 && amount <= buyerBalance);

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(buyerEOA);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.ValueLimitExceeded.selector, amount + 1));
        paymentEscrow.registerApproval(amount + 1, paymentDetails);
    }

    function test_reverts_whenZeroValue() public {
        uint256 amount = 100e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);

        vm.prank(buyerEOA);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.registerApproval(0, paymentDetails);
    }

    function test_reverts_whenAuthorizationIsVoided() public {
        uint256 amount = 100e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, amount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // First void the authorization
        vm.prank(operator);
        paymentEscrow.void(paymentDetails);

        vm.prank(buyerEOA);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.VoidAuthorization.selector, paymentDetailsHash));
        paymentEscrow.registerApproval(amount, paymentDetails);
    }

    function test_succeeds_whenRegisteringMultipleTimes() public {
        uint256 initialAmount = 100e6;
        uint256 newAmount = 150e6;

        PaymentEscrow.Authorization memory auth = _createPaymentEscrowAuthorization(buyerEOA, newAmount);
        bytes memory paymentDetails = abi.encode(auth);
        bytes32 paymentDetailsHash = keccak256(paymentDetails);

        // First registration
        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(initialAmount, paymentDetails);

        // Second registration with different amount
        vm.expectEmit(true, false, false, true);
        emit PaymentEscrow.PaymentApproved(paymentDetailsHash, newAmount);

        vm.prank(buyerEOA);
        paymentEscrow.registerApproval(newAmount, paymentDetails);
    }
}
