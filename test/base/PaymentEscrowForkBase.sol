// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC3009} from "../../src/interfaces/IERC3009.sol";

import {PaymentEscrowSmartWalletBase} from "../base/PaymentEscrowSmartWalletBase.sol";

contract PaymentEscrowForkBase is PaymentEscrowSmartWalletBase {
    // Base mainnet USDC address
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address constant USDC_WHALE = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A; // Binance

    uint256 public MAX_AMOUNT;

    // Base mainnet RPC URL
    string BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    // Contract instances
    IERC20 public usdc;

    function setUp() public virtual override {
        // Create a fork of Base mainnet
        vm.createSelectFork(BASE_RPC_URL);

        // Call parent setup to deploy contracts
        super.setUp();

        // Initialize USDC contract
        usdc = IERC20(BASE_USDC);

        vm.label(BASE_USDC, "USDC");

        MAX_AMOUNT = usdc.balanceOf(USDC_WHALE);
    }

    function createPaymentInfo(address payer, uint120 maxAmount)
        internal
        view
        returns (PaymentEscrow.PaymentInfo memory)
    {
        return PaymentEscrow.PaymentInfo({
            operator: operator,
            payer: payer,
            receiver: receiver,
            token: address(usdc),
            maxAmount: maxAmount,
            preApprovalExpiry: type(uint48).max,
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: 0
        });
    }

    // Helper function to fund an address with USDC
    function _fundWithUSDC(address recipient, uint256 amount) internal {
        // Impersonate the whale and transfer USDC
        vm.startPrank(USDC_WHALE);
        usdc.transfer(recipient, amount);
        vm.stopPrank();

        // Verify the transfer worked
        assertEq(usdc.balanceOf(recipient), amount, "USDC funding failed");
    }

    function _signERC3009ReceiveWithAuthorizationStruct(PaymentEscrow.PaymentInfo memory paymentInfo, uint256 signerPk)
        internal
        view
        override
        returns (bytes memory)
    {
        bytes32 nonce = _getHashPayerAgnostic(paymentInfo);

        bytes32 digest = _getERC3009Digest(
            paymentInfo.token,
            paymentInfo.payer,
            address(erc3009PaymentCollector),
            paymentInfo.maxAmount,
            0,
            paymentInfo.preApprovalExpiry,
            nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }
}
