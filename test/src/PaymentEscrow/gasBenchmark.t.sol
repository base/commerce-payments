// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";

contract GasBenchmarkBase is PaymentEscrowBase {
    uint256 internal constant BENCHMARK_AMOUNT = 100e6;
    uint16 internal constant BENCHMARK_FEE_BPS = 100; // 1%

    PaymentEscrow.PaymentInfo internal paymentInfo;
    bytes internal signature;

    function setUp() public virtual override {
        super.setUp();

        // Perform warmup authorization to handle first-time deployment costs associated with future potential design iterations
        PaymentEscrow.PaymentInfo memory warmupInfo = _createPaymentEscrowAuthorization(payerEOA, 1e6);
        warmupInfo.salt = 1; // different salt to avoid paymentInfo hash collision
        bytes memory warmupSignature = _signPaymentInfo(warmupInfo, payer_EOA_PK);
        mockERC3009Token.mint(payerEOA, 1e6);
        vm.prank(operator);
        paymentEscrow.authorize(warmupInfo, 1e6, hooks[TokenCollector.ERC3009], warmupSignature);

        // Create and sign payment info
        paymentInfo = _createPaymentEscrowAuthorization(payerEOA, BENCHMARK_AMOUNT);
        signature = _signPaymentInfo(paymentInfo, payer_EOA_PK);

        // Give payer tokens
        mockERC3009Token.mint(payerEOA, BENCHMARK_AMOUNT);
    }
}

contract AuthorizeGasBenchmark is GasBenchmarkBase {
    function test_authorize_benchmark() public {
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature);
    }
}

contract ChargeGasBenchmark is GasBenchmarkBase {
    function test_charge_benchmark() public {
        vm.prank(operator);
        paymentEscrow.charge(
            paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature, BENCHMARK_FEE_BPS, feeReceiver
        );
    }
}

contract CaptureGasBenchmark is GasBenchmarkBase {
    function setUp() public override {
        super.setUp();

        // Pre-authorize
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature);
    }

    function test_capture_benchmark() public {
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, BENCHMARK_AMOUNT, BENCHMARK_FEE_BPS, feeReceiver);
    }
}

contract VoidGasBenchmark is GasBenchmarkBase {
    function setUp() public override {
        super.setUp();

        // Pre-authorize
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature);
    }

    function test_void_benchmark() public {
        vm.prank(operator);
        paymentEscrow.void(paymentInfo);
    }
}

contract ReclaimGasBenchmark is GasBenchmarkBase {
    function setUp() public override {
        super.setUp();

        // Pre-authorize
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature);

        // Warp past authorization expiry
        vm.warp(paymentInfo.authorizationExpiry);
    }

    function test_reclaim_benchmark() public {
        vm.prank(payerEOA);
        paymentEscrow.reclaim(paymentInfo);
    }
}

contract RefundGasBenchmark is GasBenchmarkBase {
    function setUp() public override {
        super.setUp();

        // Pre-authorize and capture
        vm.prank(operator);
        paymentEscrow.authorize(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.ERC3009], signature);
        vm.prank(operator);
        paymentEscrow.capture(paymentInfo, BENCHMARK_AMOUNT, BENCHMARK_FEE_BPS, feeReceiver);

        // Give operator tokens for refund and approve collector
        mockERC3009Token.mint(operator, BENCHMARK_AMOUNT);
        vm.prank(operator);
        mockERC3009Token.approve(address(operatorRefundCollector), BENCHMARK_AMOUNT);
    }

    function test_refund_benchmark() public {
        vm.prank(operator);
        paymentEscrow.refund(paymentInfo, BENCHMARK_AMOUNT, hooks[TokenCollector.OperatorRefund], "");
    }
}
