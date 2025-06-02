// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {AuthCaptureEscrow} from "../AuthCaptureEscrow.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {ERC6492SignatureHandler} from "./ERC6492SignatureHandler.sol";

/// @title ERC3009PaymentCollector
///
/// @notice Collect payments using ERC-3009 ReceiveWithAuthorization signatures
///
/// @author Coinbase, Shopify
contract ERC3009PaymentCollector is TokenCollector, ERC6492SignatureHandler {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    /// @param multicall3_ Public Multicall3 singleton for safe ERC-6492 external calls
    constructor(address authCaptureEscrow_, address multicall3_)
        TokenCollector(authCaptureEscrow_)
        ERC6492SignatureHandler(multicall3_)
    {}

    /// @inheritdoc TokenCollector
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        address token = paymentInfo.token;
        address payer = paymentInfo.payer;
        uint256 maxAmount = paymentInfo.maxAmount;

        // Pull tokens into this contract
        IERC3009(token).receiveWithAuthorization({
            from: payer,
            to: address(this),
            value: maxAmount,
            validAfter: 0,
            validBefore: paymentInfo.preApprovalExpiry,
            nonce: _getHashPayerAgnostic(paymentInfo),
            signature: _handleERC6492Signature(collectorData)
        });

        // Return any excess tokens to payer
        if (maxAmount > amount) SafeERC20.safeTransfer(IERC20(token), payer, maxAmount - amount);

        // Transfer tokens directly to token store
        SafeERC20.safeTransfer(IERC20(token), tokenStore, amount);
    }
}
