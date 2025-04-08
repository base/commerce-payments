// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {TokenCollector} from "../../src/collectors/TokenCollector.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Mock token collector that does not transfer sufficient tokens
contract ERC20UnsafeTransferTokenCollector is TokenCollector {
    event PaymentPreApproved(bytes32 indexed paymentInfoHash);

    error PaymentAlreadyPreApproved(bytes32 paymentInfoHash);
    error PaymentNotPreApproved(bytes32 paymentInfoHash);
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);
    error InvalidSender(address sender, address expected);

    mapping(bytes32 => bool) public isPreApproved;

    constructor(address _paymentEscrow) TokenCollector(_paymentEscrow) {}

    /// @inheritdoc TokenCollector
    function collectorType() external pure override returns (TokenCollector.CollectorType) {
        return TokenCollector.CollectorType.Payment;
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment info
    /// @param paymentInfo PaymentInfo struct
    function preApprove(PaymentEscrow.PaymentInfo calldata paymentInfo) external {
        // check sender is buyer
        if (msg.sender != paymentInfo.payer) revert InvalidSender(msg.sender, paymentInfo.payer);

        // check status is not authorized or already pre-approved
        bytes32 paymentInfoHash = paymentEscrow.getHash(paymentInfo);
        (bool hasCollectedPayment,,) = paymentEscrow.paymentState(paymentInfoHash);
        if (hasCollectedPayment) {
            revert PaymentAlreadyCollected(paymentInfoHash);
        }
        if (isPreApproved[paymentInfoHash]) revert PaymentAlreadyPreApproved(paymentInfoHash);
        isPreApproved[paymentInfoHash] = true;
        emit PaymentPreApproved(paymentInfoHash);
    }

    function collectTokens(
        bytes32 paymentInfoHash,
        PaymentEscrow.PaymentInfo calldata paymentInfo,
        uint256,
        bytes calldata
    ) external override onlyPaymentEscrow {
        if (!isPreApproved[paymentInfoHash]) {
            revert PaymentNotPreApproved(paymentInfoHash);
        }

        // Get treasury address
        address treasury = paymentEscrow.getOperatorTreasury(paymentInfo.operator);

        // transfer too few token to treasury
        IERC20(paymentInfo.token).transferFrom(paymentInfo.payer, treasury, paymentInfo.maxAmount - 1);
    }
}
