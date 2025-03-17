// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {PublicERC6492Validator} from "spend-permissions/PublicERC6492Validator.sol";
import {IERC3009} from "../../src/IERC3009.sol";
import {MockERC3009Token} from "../mocks/MockERC3009Token.sol";

contract PaymentEscrowBase is Test {
    PaymentEscrow public paymentEscrow;
    PublicERC6492Validator public erc6492Validator;
    MockERC3009Token public mockERC3009Token;

    address public operator;
    address public captureAddress;
    address public buyerEOA;
    address public feeRecipient;
    uint16 constant FEE_BPS = 100; // 1%
    uint256 internal constant BUYER_EOA_PK = 0x1234;

    function setUp() public virtual {
        erc6492Validator = new PublicERC6492Validator();
        paymentEscrow = new PaymentEscrow(address(erc6492Validator));
        mockERC3009Token = new MockERC3009Token("Mock USDC", "mUSDC", 6);

        operator = makeAddr("operator");
        captureAddress = makeAddr("captureAddress");
        buyerEOA = vm.addr(BUYER_EOA_PK); // Derive address from private key
        feeRecipient = makeAddr("feeRecipient");

        mockERC3009Token.mint(buyerEOA, 1000e6);
    }

    function _createPaymentEscrowAuthorization(address buyer, uint256 value)
        internal
        view
        returns (PaymentEscrow.PaymentDetails memory)
    {
        return PaymentEscrow.PaymentDetails({
            token: address(mockERC3009Token),
            buyer: buyer,
            captureAddress: captureAddress,
            value: value,
            validBefore: type(uint48).max,
            captureDeadline: type(uint48).max,
            operator: operator,
            feeBps: FEE_BPS,
            feeRecipient: feeRecipient,
            salt: 0
        });
    }

    function _signPaymentDetails(PaymentEscrow.PaymentDetails memory paymentDetails, uint256 signerPk)
        internal
        returns (bytes memory)
    {
        return _signERC3009({
            from: paymentDetails.buyer,
            to: address(paymentEscrow),
            value: paymentDetails.value,
            validAfter: 0,
            validBefore: paymentDetails.validBefore,
            nonce: keccak256(abi.encode(paymentDetails)),
            signerPk: signerPk
        });
    }

    function _signERC3009(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                mockERC3009Token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(), from, to, value, validAfter, validBefore, nonce
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", mockERC3009Token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }
}
