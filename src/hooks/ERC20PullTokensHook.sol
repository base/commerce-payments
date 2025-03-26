// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../interfaces/IPullTokensHook.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "../PaymentEscrow.sol";

contract ERC20PullTokensHook is IPullTokensHook {
    event PaymentApproved(bytes32 indexed paymentDetailsHash);

    error PaymentAlreadyPreApproved(bytes32 paymentDetailsHash);
    error PaymentNotApproved(bytes32 paymentDetailsHash);
    error PaymentAlreadyAuthorized(bytes32 paymentDetailsHash);
    error InvalidSender(address sender);

    mapping(bytes32 => bool) public isPreApproved;

    PaymentEscrow public immutable paymentEscrow;

    constructor(address _paymentEscrow) {
        paymentEscrow = PaymentEscrow(_paymentEscrow);
    }

    /// @notice Registers buyer's token approval for a specific payment
    /// @dev Must be called by the buyer specified in the payment details
    /// @param paymentDetails PaymentDetails struct
    function preApprove(PaymentEscrow.PaymentDetails calldata paymentDetails) external {
        // check sender is buyer
        if (msg.sender != paymentDetails.payer) revert InvalidSender(msg.sender);

        // check status is not authorized or already pre-approved
        bytes32 paymentDetailsHash = keccak256(abi.encode(paymentDetails));
        if (paymentEscrow.isAuthorized(paymentDetailsHash)) revert PaymentAlreadyAuthorized(paymentDetailsHash);
        if (isPreApproved[paymentDetailsHash]) revert PaymentAlreadyPreApproved(paymentDetailsHash);
        isPreApproved[paymentDetailsHash] = true;
        emit PaymentApproved(paymentDetailsHash);
    }

    function pullTokens(
        PaymentEscrow.PaymentDetails calldata paymentDetails,
        bytes32 paymentDetailsHash,
        uint256 value,
        bytes calldata,
        bytes calldata
    ) external override {
        if (!isPreApproved[paymentDetailsHash]) {
            revert PaymentNotApproved(paymentDetailsHash);
        }
        SafeTransferLib.safeTransferFrom(paymentDetails.token, paymentDetails.payer, msg.sender, value);
    }
}
