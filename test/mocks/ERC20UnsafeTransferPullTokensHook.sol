// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IPullTokensHook} from "../../src/interfaces/IPullTokensHook.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Mock hook that does not transfer sufficient tokens
contract ERC20UnsafeTransferPullTokensHook is IPullTokensHook {
    event PaymentApproved(bytes32 indexed paymentDetailsHash);

    error PaymentAlreadyPreApproved(bytes32 paymentDetailsHash);
    error PaymentNotApproved(bytes32 paymentDetailsHash);
    error PaymentAlreadyAuthorized(bytes32 paymentDetailsHash);
    error InvalidSender(address sender);

    mapping(bytes32 => bool) public isPreApproved;

    constructor(address _paymentEscrow) IPullTokensHook(_paymentEscrow) {}

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

    function pullTokens(PaymentEscrow.PullTokensData memory pullTokensData) external override onlyPaymentEscrow {
        if (!isPreApproved[pullTokensData.nonce]) {
            revert PaymentNotApproved(pullTokensData.nonce);
        }
        // transfer too few token to escrow
        IERC20(pullTokensData.token).transferFrom(
            pullTokensData.payer, address(paymentEscrow), pullTokensData.value - 1
        );
    }
}
