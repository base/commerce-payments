// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";
import {TokenCollector} from "./TokenCollector.sol";
import {ERC6492SignatureHandler} from "./ERC6492SignatureHandler.sol";

/// @title ERC3009PaymentCollector
/// @notice Collect payments using ERC-3009 ReceiveWithAuthorization signatures
/// @author Coinbase
contract ERC3009PaymentCollector is TokenCollector, ERC6492SignatureHandler {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Payment;

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    /// @param multicall3_ Public Multicall3 singleton for safe ERC-6492 external calls
    constructor(address paymentEscrow_, address multicall3_)
        TokenCollector(paymentEscrow_)
        ERC6492SignatureHandler(multicall3_)
    {}

    /// @inheritdoc TokenCollector
    function _collectTokens(
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        address token = paymentInfo.token;
        address payer = paymentInfo.payer;
        uint256 maxAmount = paymentInfo.maxAmount;

        // Apply ERC-6492 preparation call if present
        bytes memory signature = _handleERC6492Signature(collectorData);

        // Construct nonce as payer-less payment info hash for offchain preparation convenience
        bytes32 nonce = _getHashPayerAgnostic(paymentInfo);

        // Pull tokens into this contract
        IERC3009(token).receiveWithAuthorization({
            from: payer,
            to: address(this),
            value: maxAmount,
            validAfter: 0,
            validBefore: paymentInfo.preApprovalExpiry,
            nonce: nonce,
            signature: signature
        });

        // Return any excess tokens to payer
        uint256 excess = maxAmount - amount;
        if (excess > 0) SafeERC20.safeTransfer(IERC20(token), payer, excess);

        // Transfer tokens directly to token store
        SafeERC20.safeTransfer(IERC20(token), tokenStore, amount);
    }
}
