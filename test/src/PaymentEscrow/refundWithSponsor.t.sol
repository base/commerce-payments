// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";

contract RefundWithSponsorTest is PaymentEscrowBase {
    address _sponsor;
    uint256 constant _SPONSOR_PK = 0x12345; // Example private key for sponsor

    function setUp() public virtual override {
        super.setUp();
        _sponsor = vm.addr(_SPONSOR_PK);
    }

    // function test_reverts_ifValueIsZero(uint120 initialAmount, uint48 refundDeadline, uint256 refundSalt) public {
    //     vm.assume(initialAmount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: initialAmount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, initialAmount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(initialAmount, paymentDetails, signature, "");
    //     paymentEscrow.capture(initialAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         value: 0,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(PaymentEscrow.ZeroAmount.selector);
    //     paymentEscrow.refundWithSponsor(0, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    // }

    // function test_refundWithSponsor_reverts_whenAmountOverflows(uint256 overflowValue) public {
    //     vm.assume(overflowValue > type(uint120).max);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: 1});

    //     uint48 refundDeadline = uint48(block.timestamp + 1 days);
    //     uint256 refundSalt = 123;
    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: 1,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.AmountOverflow.selector, overflowValue, type(uint120).max));
    //     paymentEscrow.refundWithSponsor(
    //         overflowValue, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature
    //     );
    // }

    // function test_reverts_ifSenderIsInvalid(
    //     uint120 amount,
    //     address invalidSender,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(amount > 0);
    //     vm.assume(invalidSender != operator);
    //     vm.assume(invalidSender != receiver);
    //     vm.assume(invalidSender != address(0));
    //     vm.assume(refundDeadline > block.timestamp);

    //     mockERC3009Token.mint(payerEOA, amount);
    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(invalidSender);
    //     vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
    //     paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    // }

    // function test_reverts_ifValueIsGreaterThanCaptured(
    //     uint120 captureAmount,
    //     uint120 refundAmount,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(refundAmount > captureAmount);
    //     vm.assume(refundAmount > 0);
    //     vm.assume(captureAmount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, value: captureAmount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, captureAmount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(captureAmount, paymentDetails, signature, "");
    //     paymentEscrow.capture(captureAmount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         value: refundAmount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, refundAmount, captureAmount)
    //     );
    //     paymentEscrow.refundWithSponsor(
    //         refundAmount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature
    //     );
    // }

    // function test_reverts_ifSignatureIsInvalid(
    //     uint120 amount,
    //     bytes calldata invalidSignature,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(amount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, amount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     vm.prank(operator);
    //     vm.expectRevert(); // Expect revert from invalid signature
    //     paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, invalidSignature);
    // }

    // function test_reverts_ifSaltIsIncorrect(
    //     uint120 amount,
    //     uint256 incorrectSalt,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(amount > 0);
    //     vm.assume(incorrectSalt != refundSalt);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, amount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(); // Expect revert from mismatched salt
    //     paymentEscrow.refundWithSponsor(
    //         amount, paymentDetails, _sponsor, refundDeadline, incorrectSalt, sponsorSignature
    //     );
    // }

    // function test_reverts_ifSponsorIsIncorrect(
    //     uint120 amount,
    //     address incorrectSponsor,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(amount > 0);
    //     vm.assume(incorrectSponsor != _sponsor);
    //     vm.assume(incorrectSponsor != address(0));
    //     vm.assume(refundDeadline > block.timestamp);

    //     mockERC3009Token.mint(payerEOA, amount);
    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(); // Expect revert from mismatched sponsor
    //     paymentEscrow.refundWithSponsor(
    //         amount, paymentDetails, incorrectSponsor, refundDeadline, refundSalt, sponsorSignature
    //     );
    // }

    // function test_reverts_ifRefundDeadlineIsIncorrect(
    //     uint120 amount,
    //     uint48 incorrectDeadline,
    //     uint48 refundDeadline,
    //     uint256 refundSalt
    // ) public {
    //     vm.assume(amount > 0);
    //     vm.assume(incorrectDeadline != refundDeadline);
    //     vm.assume(incorrectDeadline > block.timestamp); // Must be future timestamp
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, amount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.prank(operator);
    //     vm.expectRevert(); // Expect revert from mismatched deadline
    //     paymentEscrow.refundWithSponsor(
    //         amount, paymentDetails, _sponsor, incorrectDeadline, refundSalt, sponsorSignature
    //     );
    // }

    // function test_succeeds_ifCalledByOperator(uint120 amount, uint48 refundDeadline, uint256 refundSalt) public {
    //     vm.assume(amount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     mockERC3009Token.mint(payerEOA, amount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     // Fund sponsor
    //     mockERC3009Token.mint(_sponsor, amount);

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         value: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
    //     uint256 sponsorBalanceBefore = mockERC3009Token.balanceOf(_sponsor);

    //     vm.prank(operator);
    //     paymentEscrow.refundWithSponsor(
    //         amount,
    //         paymentDetails,
    //         PaymentEscrow.SponsoredRefundDetails({
    //             sponsor: _sponsor,
    //             refundDeadline: refundDeadline,
    //             tokenCollector: address(hooks[TokenCollector.ERC3009]),
    //             refundSalt: refundSalt,
    //             signature: sponsorSignature,
    //             collectorData: ""
    //         })
    //     );

    //     assertEq(mockERC3009Token.balanceOf(_sponsor), sponsorBalanceBefore - amount);
    //     assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + amount);
    // }

    // function test_succeeds_ifCalledByreceiver(uint120 amount, uint48 refundDeadline, uint256 refundSalt) public {
    //     vm.assume(amount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     // Mint tokens for payer
    //     mockERC3009Token.mint(payerEOA, amount);

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     // Fund sponsor with enough tokens
    //     mockERC3009Token.mint(_sponsor, amount);

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     uint256 payerBalanceBefore = mockERC3009Token.balanceOf(payerEOA);
    //     uint256 sponsorBalanceBefore = mockERC3009Token.balanceOf(_sponsor);

    //     vm.prank(receiver);
    //     paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);

    //     assertEq(mockERC3009Token.balanceOf(_sponsor), sponsorBalanceBefore - amount);
    //     assertEq(mockERC3009Token.balanceOf(payerEOA), payerBalanceBefore + amount);
    // }

    // function test_emitsExpectedEvents(uint120 amount, uint48 refundDeadline, uint256 refundSalt) public {
    //     vm.assume(amount > 0);
    //     vm.assume(refundDeadline > block.timestamp);

    //     PaymentEscrow.PaymentDetails memory paymentDetails =
    //         _createPaymentEscrowAuthorization({payer: payerEOA, maxAmount: amount});
    //     bytes memory signature = _signPaymentDetails(paymentDetails, payer_EOA_PK);

    //     // Mint tokens for payer
    //     mockERC3009Token.mint(payerEOA, amount);

    //     bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

    //     // First authorize and capture
    //     vm.startPrank(operator);
    //     paymentEscrow.authorize(amount, paymentDetails, signature, "");
    //     paymentEscrow.capture(amount, paymentDetails, paymentDetails.minFeeBps, paymentDetails.feeRecipient);
    //     vm.stopPrank();

    //     // Fund sponsor with enough tokens
    //     mockERC3009Token.mint(_sponsor, amount);

    //     bytes memory sponsorSignature = _signRefundAuthorization({
    //         paymentDetails: paymentDetails,
    //         maxAmount: amount,
    //         sponsorAddress: _sponsor,
    //         deadline: refundDeadline,
    //         salt: refundSalt,
    //         privateKey: _SPONSOR_PK
    //     });

    //     vm.expectEmit(true, true, false, true);
    //     emit PaymentEscrow.PaymentRefunded(paymentDetailsHash, amount, operator);

    //     vm.prank(operator);
    //     paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    // }

    // Helper function to sign refund authorization
    function _signRefundAuthorization(
        PaymentEscrow.PaymentDetails memory paymentDetails,
        uint120 value,
        address sponsorAddress,
        uint48 deadline,
        uint256 salt,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        bytes32 nonce = keccak256(abi.encode(paymentDetailsHash, salt));

        // Use the same ERC3009 signing pattern as in PaymentEscrowBase
        bytes32 structHash = keccak256(
            abi.encode(
                mockERC3009Token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                sponsorAddress, // from
                address(hooks[TokenCollector.ERC3009]), // to
                value, // value
                0, // validAfter
                deadline, // validBefore
                nonce // nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mockERC3009Token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
