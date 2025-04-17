// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";

import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";

contract ERC3009PaymentCollectorTest is PaymentEscrowSmartWalletBase {
    function test_collectTokens_reverts_whenCalledByNonPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyPaymentEscrow.selector));
        erc3009PaymentCollector.collectTokens(paymentInfo, amount, "");
    }

    function test_collectTokens_succeeds_whenCalledByPaymentEscrow(uint120 amount) public {
        vm.assume(amount > 0);
        MockERC3009Token(address(mockERC3009Token)).mint(payerEOA, amount);
        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(payerEOA, amount);
        bytes memory signature = _signERC3009ReceiveWithAuthorizationStruct(paymentInfo, payer_EOA_PK);
        vm.prank(address(paymentEscrow));
        erc3009PaymentCollector.collectTokens(paymentInfo, amount, signature);
    }

    function test_collectTokens_succeeds_withERC6492Signature(uint120 amount) public {
        vm.assume(amount > 0);

        mockERC3009Token.mint(smartWalletCounterfactual, amount);

        assertEq(smartWalletCounterfactual.code.length, 0, "Smart wallet should not be deployed yet");

        PaymentEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(smartWalletCounterfactual, amount);

        bytes memory signature = _signSmartWalletERC3009WithERC6492(paymentInfo, COUNTERFACTUAL_WALLET_OWNER_PK, 0);

        vm.prank(address(paymentEscrow));
        erc3009PaymentCollector.collectTokens(paymentInfo, amount, signature);

        assertEq(
            mockERC3009Token.balanceOf(paymentEscrow.getTokenStore(paymentInfo.operator)),
            amount,
            "Token store balance did not increase by correct amount"
        );
        assertEq(mockERC3009Token.balanceOf(smartWalletCounterfactual), 0, "Smart wallet balance should be 0");
    }
}
