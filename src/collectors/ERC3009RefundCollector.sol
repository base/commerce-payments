// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC3009} from "../interfaces/IERC3009.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";
import {TokenCollector} from "./TokenCollector.sol";

/// @title ERC3009RefundCollector
/// @notice Collect refunds using ERC-3009 ReceiveWithAuthorization signatures from liquidity providers
/// @author Coinbase
contract ERC3009RefundCollector is TokenCollector {
    /// @notice Data required for ERC-3009 refund collection
    struct RefundData {
        /// @notice Address providing the refund liquidity
        address sponsor;
        /// @notice Expiry timestamp for the refund authorization
        uint48 expiry;
        /// @notice Salt to ensure unique nonces across potential for multiple refunds of same payment
        uint256 salt;
        /// @notice ERC-3009 authorization signature
        bytes signature;
    }

    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Refund;

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that calls to collect tokens
    constructor(address paymentEscrow_) TokenCollector(paymentEscrow_) {}

    /// @inheritdoc TokenCollector
    function _collectTokens(
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) internal override {
        address token = paymentInfo.token;

        // Decode the refund liquidity details from collectorData
        RefundData memory refundData = abi.decode(collectorData, (RefundData));

        // Pull tokens into this contract
        IERC3009(token).receiveWithAuthorization({
            from: refundData.sponsor,
            to: address(this),
            value: amount,
            validAfter: 0,
            validBefore: refundData.expiry,
            nonce: keccak256(abi.encode(paymentInfo, refundData.salt)),
            signature: refundData.signature
        });

        // Transfer tokens directly to token store
        SafeERC20.safeTransfer(IERC20(token), tokenStore, amount);
    }
}
