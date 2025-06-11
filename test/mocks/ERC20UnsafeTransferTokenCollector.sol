// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {TokenCollector} from "../../src/collectors/TokenCollector.sol";
import {AuthCaptureEscrow} from "../../src/AuthCaptureEscrow.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Mock token collector that does not transfer sufficient tokens
contract ERC20UnsafeTransferTokenCollector is TokenCollector {
    event PaymentPreApproved(bytes32 indexed paymentInfoHash);

    error PaymentAlreadyPreApproved(bytes32 paymentInfoHash);
    error PaymentNotPreApproved(bytes32 paymentInfoHash);
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);
    error InvalidSender(address sender, address expected);

    mapping(bytes32 => bool) public isPreApproved;

    constructor(address _escrow) TokenCollector(_escrow) {}

    /// @inheritdoc TokenCollector
    function collectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
    }

    /// @notice Registers payer's token approval for a specific payment
    /// @dev Must be called by the payer specified in the payment info
    /// @param paymentInfo PaymentInfo struct
    function preApprove(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // check sender is payer
        if (msg.sender != paymentInfo.payer) revert InvalidSender(msg.sender, paymentInfo.payer);

        // check status is not authorized or already pre-approved
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        (bool hasCollectedPayment,,) = authCaptureEscrow.paymentState(paymentInfoHash);
        if (hasCollectedPayment) {
            revert PaymentAlreadyCollected(paymentInfoHash);
        }
        if (isPreApproved[paymentInfoHash]) revert PaymentAlreadyPreApproved(paymentInfoHash);
        isPreApproved[paymentInfoHash] = true;
        emit PaymentPreApproved(paymentInfoHash);
    }

    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256,
        bytes calldata
    ) internal override {
        bytes32 paymentInfoHash = authCaptureEscrow.getHash(paymentInfo);
        if (!isPreApproved[paymentInfoHash]) {
            revert PaymentNotPreApproved(paymentInfoHash);
        }

        // transfer too few token to tokenStore
        IERC20(paymentInfo.token).transferFrom(paymentInfo.payer, tokenStore, paymentInfo.maxAmount - 1);
    }
}
