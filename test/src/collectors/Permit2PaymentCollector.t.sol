// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";

contract Permit2PaymentCollectorTest is PaymentEscrowBase {
    function test_collectTokens_reverts_whenCalledByNonPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        permit2PaymentCollector.collectTokens(paymentInfo, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        bytes memory signature = _signPermit2Transfer({
            token: address(mockERC3009Token),
            amount: amount,
            deadline: paymentInfo.preApprovalExpiry,
            nonce: uint256(_getHashPayerAgnostic(paymentInfo)),
            privateKey: payer_EOA_PK
        });
        vm.prank(address(paymentEscrow));
        permit2PaymentCollector.collectTokens(paymentInfo, amount, signature);
    }
}
