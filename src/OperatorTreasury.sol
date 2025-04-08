// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PaymentEscrow} from "./PaymentEscrow.sol";

/// @title OperatorTreasury
/// @notice Holds funds for a single operator's payments
/// @dev Created by PaymentEscrow to isolate operator funds

contract OperatorTreasury {
    /// @notice The PaymentEscrow contract that created this treasury
    address public immutable escrow;

    error OnlyEscrow();
    error TransferFailed();

    constructor(PaymentEscrow escrow_) {
        escrow = address(escrow_);
    }

    /// @notice Only allow the escrow contract to call
    modifier onlyEscrow() {
        if (msg.sender != escrow) revert OnlyEscrow();
        _;
    }

    /// @notice Send tokens to a recipient, called by escrow during capture/refund
    /// @param token The token being received
    /// @param amount Amount of tokens to receive
    /// @param recipient Address to receive the tokens
    function sendTokens(address token, uint256 amount, address recipient) external onlyEscrow returns (bool) {
        SafeTransferLib.safeTransfer(token, recipient, amount);
        return true;
    }
}
