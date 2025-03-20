// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PaymentEscrowBase} from "../../base/PaymentEscrowBase.sol";
import {IPermit2} from "../../../src/interfaces/IPermit2.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Constants} from "../../utils/Constants.sol";
import {ISignatureTransfer} from "../../../src/interfaces/ISignatureTransfer.sol";

contract Permit2Test is PaymentEscrowBase {
    // Permit2 constants
    bytes32 constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Non-ERC3009 token to force Permit2 path
    MockERC20 public plainToken;

    function setUp() public override {
        // Deploy a regular ERC20 without ERC3009
        plainToken = new MockERC20("Plain Token", "PLAIN", 18);
        
        // Etch Permit2 bytecode at canonical address
        vm.etch(PERMIT2_ADDRESS, Constants.PERMIT2_BYTECODE);
        
        // Initialize PaymentEscrow with real Permit2
        super.setUp();

        // Mint some tokens to the buyer
        plainToken.mint(buyerEOA, 1000e18);
        
        // Buyer needs to approve Permit2 to spend their tokens
        vm.prank(buyerEOA);
        plainToken.approve(PERMIT2_ADDRESS, type(uint256).max);
    }

    function _signPermit2Transfer(
        address token,
        uint256 amount,
        address owner,
        uint256 deadline,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        // Create TokenPermissions struct
        ISignatureTransfer.TokenPermissions memory permitted = ISignatureTransfer.TokenPermissions({
            token: token,
            amount: amount
        });

        // Create PermitTransferFrom struct
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: permitted,
            nonce: nonce,
            deadline: deadline
        });

        // Get domain separator from Permit2
        bytes32 domainSeparator = IPermit2(PERMIT2_ADDRESS).DOMAIN_SEPARATOR();

        // Hash the TokenPermissions struct
        bytes32 tokenPermissionsHash = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));

        // Create the full message hash
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(
                    _PERMIT_TRANSFER_FROM_TYPEHASH,
                    tokenPermissionsHash,
                    address(paymentEscrow), // spender
                    permit.nonce,
                    permit.deadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }

    function test_authorize_succeeds_withPermit2Fallback() public {
        uint256 amount = 100e18;
        
        PaymentEscrow.PaymentDetails memory paymentDetails = 
            _createPaymentEscrowAuthorization({
                buyer: buyerEOA,
                value: amount,
                token: address(plainToken)  // Use our non-ERC3009 token
            });

        // Generate Permit2 signature
        bytes memory signature = _signPermit2Transfer({
            token: address(plainToken),
            amount: amount,
            owner: buyerEOA,
            deadline: block.timestamp + 1 days,
            nonce: IPermit2(PERMIT2_ADDRESS).nonces(buyerEOA),
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