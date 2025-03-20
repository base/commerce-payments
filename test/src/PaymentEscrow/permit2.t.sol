// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "../../../src/PaymentEscrow.sol";
import {Test, console} from "forge-std/Test.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";
import {MockERC3009Token} from "../../mocks/MockERC3009Token.sol";

// Import Permit2's interfaces and libraries
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {PermitHash} from "permit2/libraries/PermitHash.sol";

contract Permit2Test is PaymentEscrowBase {
    using PermitHash for ISignatureTransfer.PermitTransferFrom;

    // Permit2 constants
    bytes32 constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    // Non-ERC3009 token to force Permit2 path
    MockERC20 public plainToken;

    function setUp() public override {
        // Initialize PaymentEscrow with Permit2 first
        super.setUp();

        // Deploy a regular ERC20 without ERC3009
        plainToken = new MockERC20("Plain Token", "PLAIN", 18);

        // Mint some tokens to the buyer
        plainToken.mint(buyerEOA, 1000e18);

        // Buyer needs to approve Permit2 to spend their tokens
        vm.startPrank(buyerEOA);
        plainToken.approve(address(paymentEscrow.permit2()), type(uint256).max);
        vm.stopPrank();
    }

    function _signPermit2Transfer(address token, uint256 amount, uint256 deadline, uint256 nonce, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        // Create PermitTransferFrom struct
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
            nonce: nonce,
            deadline: deadline
        });

        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount));
        bytes32 permitHash = keccak256(
            abi.encode(
                _PERMIT_TRANSFER_FROM_TYPEHASH,
                tokenPermissionsHash,
                address(paymentEscrow),
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 domainSeparator = IPermit2(address(paymentEscrow.permit2())).DOMAIN_SEPARATOR();

        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }

    function test_authorize_succeeds_withPermit2Fallback() public {
        uint256 amount = 100e18;

        PaymentEscrow.PaymentDetails memory paymentDetails =
            _createPaymentEscrowAuthorization({buyer: buyerEOA, value: amount, token: address(plainToken)});

        // Generate Permit2 signature using the same deadline as paymentDetails
        bytes memory signature = _signPermit2Transfer({
            token: address(plainToken),
            amount: amount,
            deadline: paymentDetails.authorizeDeadline,
            nonce: uint256(keccak256(abi.encode(paymentDetails))),
            privateKey: BUYER_EOA_PK
        });

        // Should succeed via Permit2 fallback
        vm.prank(operator);
        paymentEscrow.authorize(amount, paymentDetails, signature);

        // Verify the transfer worked
        assertEq(plainToken.balanceOf(address(paymentEscrow)), amount);
        assertEq(plainToken.balanceOf(buyerEOA), 900e18);
    }
}
