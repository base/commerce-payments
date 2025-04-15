// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowSmartWalletBase} from "../../base/PaymentEscrowSmartWalletBase.sol";
import {TokenCollector} from "../../../src/collectors/TokenCollector.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";
import {MockStandardERC3009Token} from "../../mocks/MockStandardERC3009Token.sol";

contract ERC3009PaymentCollectorTest is PaymentEscrowSmartWalletBase {
    MockStandardERC3009Token public mockStandardToken;

    function setUp() public override {
        super.setUp();
        mockStandardToken = new MockStandardERC3009Token("Mock Standard ERC3009", "MST", 18);
    }

    // Helper function specific to MockStandardERC3009Token
    function _signStandardERC3009Authorization(PaymentEscrow.PaymentInfo memory paymentInfo, uint256 signerPk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 nonce = _getHashPayerAgnostic(paymentInfo);

        bytes32 structHash = keccak256(
            abi.encode(
                mockStandardToken.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                paymentInfo.payer,
                address(erc3009PaymentCollector),
                paymentInfo.maxAmount,
                0,
                paymentInfo.preApprovalExpiry,
                nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mockStandardToken.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

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

    function test_collectTokens_succeeds_withStandardERC3009(uint120 amount) public {
        vm.assume(amount > 0);
        mockStandardToken.mint(payerEOA, amount);

        // Create payment info with standard token
        PaymentEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo({payer: payerEOA, maxAmount: amount, token: address(mockStandardToken)});

        // Use our new signing function instead of the USDC one
        bytes memory signature = _signStandardERC3009Authorization(paymentInfo, payer_EOA_PK);
        uint256 initialBalance = mockStandardToken.balanceOf(payerEOA);

        vm.prank(address(paymentEscrow));
        erc3009PaymentCollector.collectTokens(paymentInfo, amount, signature);

        address tokenStore = paymentEscrow.getTokenStore(paymentInfo.operator);
        assertEq(mockStandardToken.balanceOf(tokenStore), amount);
        assertEq(mockStandardToken.balanceOf(payerEOA), initialBalance - amount);
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
