// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";

import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";

contract Permit2PaymentCollectorTest is PaymentEscrowSmartWalletBase {
    function setUp() public override {
        super.setUp();
        vm.prank(address(smartWalletDeployed));
        mockERC20Token.approve(address(permit2), type(uint256).max);
        vm.prank(smartWalletCounterfactual);
        mockERC20Token.approve(address(permit2), type(uint256).max);
    }

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

    function test_collectTokens_succeeds_withERC6492Signature(uint120 amount) public {
        vm.assume(amount > 0);

        mockERC20Token.mint(smartWalletCounterfactual, amount);

        assertEq(smartWalletCounterfactual.code.length, 0, "Smart wallet should not be deployed yet");

        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(smartWalletCounterfactual, amount, address(mockERC20Token));

        bytes memory signature = _signPermit2WithERC6492(paymentInfo, COUNTERFACTUAL_WALLET_OWNER_PK, 0);

        vm.prank(address(paymentEscrow));
        permit2PaymentCollector.collectTokens(paymentInfo, amount, signature);

        assertEq(
            mockERC20Token.balanceOf(paymentEscrow.getTokenStore(paymentInfo.operator)),
            amount,
            "Token store balance did not increase by correct amount"
        );
        assertEq(mockERC20Token.balanceOf(smartWalletCounterfactual), 0, "Smart wallet balance should be 0");
    }
}
