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

    function test_reverts_ifValueIsZero(uint120 initialAmount, uint48 refundDeadline, uint256 refundSalt) public {
        vm.assume(initialAmount > 0);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: initialAmount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, initialAmount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(initialAmount, paymentDetails, signature);
        paymentEscrow.capture(initialAmount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: 0,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(operator);
        vm.expectRevert(PaymentEscrow.ZeroValue.selector);
        paymentEscrow.refundWithSponsor(0, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    }

    function test_reverts_ifSenderIsInvalid(address invalidSender, uint48 refundDeadline, uint256 refundSalt) public {
        vm.assume(invalidSender != operator);
        vm.assume(invalidSender != captureAddress);
        vm.assume(invalidSender != address(0));
        vm.assume(refundDeadline > block.timestamp);

        uint256 amount = 100e6;
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(PaymentEscrow.InvalidSender.selector, invalidSender));
        paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    }

    function test_reverts_ifValueIsGreaterThanCaptured(
        uint120 captureAmount,
        uint120 refundAmount,
        uint48 refundDeadline,
        uint256 refundSalt
    ) public {
        vm.assume(refundAmount > captureAmount);
        vm.assume(refundAmount > 0);
        vm.assume(captureAmount > 0);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: captureAmount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, captureAmount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(captureAmount, paymentDetails, signature);
        paymentEscrow.capture(captureAmount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: refundAmount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentEscrow.RefundExceedsCapture.selector, refundAmount, captureAmount)
        );
        paymentEscrow.refundWithSponsor(
            refundAmount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature
        );
    }

    function test_reverts_ifSignatureIsInvalid(
        uint256 amount,
        bytes calldata invalidSignature,
        uint48 refundDeadline,
        uint256 refundSalt
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(); // Expect revert from invalid signature
        paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, invalidSignature);
    }

    function test_reverts_ifSaltIsIncorrect(
        uint256 amount,
        uint256 incorrectSalt,
        uint48 refundDeadline,
        uint256 refundSalt
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(incorrectSalt != refundSalt);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(operator);
        vm.expectRevert(); // Expect revert from mismatched salt
        paymentEscrow.refundWithSponsor(
            amount, paymentDetails, _sponsor, refundDeadline, incorrectSalt, sponsorSignature
        );
    }

    function test_reverts_ifSponsorIsIncorrect(address incorrectSponsor, uint48 refundDeadline, uint256 refundSalt)
        public
    {
        vm.assume(incorrectSponsor != _sponsor);
        vm.assume(incorrectSponsor != address(0));
        vm.assume(refundDeadline > block.timestamp);

        uint256 amount = 100e6;
        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(operator);
        vm.expectRevert(); // Expect revert from mismatched sponsor
        paymentEscrow.refundWithSponsor(
            amount, paymentDetails, incorrectSponsor, refundDeadline, refundSalt, sponsorSignature
        );
    }

    function test_reverts_ifRefundDeadlineIsIncorrect(
        uint256 amount,
        uint48 incorrectDeadline,
        uint48 refundDeadline,
        uint256 refundSalt
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(incorrectDeadline != refundDeadline);
        vm.assume(incorrectDeadline > block.timestamp); // Must be future timestamp
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.prank(operator);
        vm.expectRevert(); // Expect revert from mismatched deadline
        paymentEscrow.refundWithSponsor(
            amount, paymentDetails, _sponsor, incorrectDeadline, refundSalt, sponsorSignature
        );
    }

    function test_succeeds_ifCalledByOperator(uint256 amount, uint48 refundDeadline, uint256 refundSalt) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        mockERC3009Token.mint(buyerEOA, amount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        // Fund sponsor
        mockERC3009Token.mint(_sponsor, amount);

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 sponsorBalanceBefore = mockERC3009Token.balanceOf(_sponsor);

        vm.prank(operator);
        paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);

        assertEq(mockERC3009Token.balanceOf(_sponsor), sponsorBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore + amount);
    }

    function test_succeeds_ifCalledByCaptureAddress(uint256 amount, uint48 refundDeadline, uint256 refundSalt) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Mint tokens for buyer
        mockERC3009Token.mint(buyerEOA, amount);

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        // Fund sponsor with enough tokens
        mockERC3009Token.mint(_sponsor, amount);

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        uint256 buyerBalanceBefore = mockERC3009Token.balanceOf(buyerEOA);
        uint256 sponsorBalanceBefore = mockERC3009Token.balanceOf(_sponsor);

        vm.prank(captureAddress);
        paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);

        assertEq(mockERC3009Token.balanceOf(_sponsor), sponsorBalanceBefore - amount);
        assertEq(mockERC3009Token.balanceOf(buyerEOA), buyerBalanceBefore + amount);
    }

    function test_emitsExpectedEvents(uint256 amount, uint48 refundDeadline, uint256 refundSalt) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint120).max);
        vm.assume(refundDeadline > block.timestamp);

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount});
        bytes memory signature = _signPaymentDetails(paymentDetails, BUYER_EOA_PK);

        // Mint tokens for buyer
        mockERC3009Token.mint(buyerEOA, amount);

        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));

        // First authorize and capture
        vm.startPrank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);
        paymentEscrow.capture(amount, paymentDetails);
        vm.stopPrank();

        // Fund sponsor with enough tokens
        mockERC3009Token.mint(_sponsor, amount);

        bytes memory sponsorSignature = _signRefundAuthorization({
            paymentDetails: paymentDetails,
            value: amount,
            sponsorAddress: _sponsor,
            deadline: refundDeadline,
            salt: refundSalt,
            privateKey: _SPONSOR_PK
        });

        vm.expectEmit(true, true, false, true);
        emit PaymentEscrow.PaymentRefunded(paymentDetailsHash, amount, operator);

        vm.prank(operator);
        paymentEscrow.refundWithSponsor(amount, paymentDetails, _sponsor, refundDeadline, refundSalt, sponsorSignature);
    }

    // Helper function to sign refund authorization
    function _signRefundAuthorization(
        PaymentEscrow.PaymentDetails memory paymentDetails,
        uint256 value,
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
                address(paymentEscrow), // to
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
