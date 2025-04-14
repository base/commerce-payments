// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title TokenStore
/// @notice Holds funds for a single operator's payments
/// @dev Created by PaymentEscrow to isolate operator funds
contract TokenStore {
    /// @notice The PaymentEscrow contract that created this token store
    address public immutable escrow;

    error OnlyEscrow();

    constructor(address escrow_) {
        escrow = escrow_;
    }

    /// @notice Send tokens to a recipient, called by escrow during capture/refund
    /// @param token The token being received
    /// @param amount Amount of tokens to receive
    /// @param recipient Address to receive the tokens
    function sendTokens(address token, uint256 amount, address recipient) external returns (bool) {
        if (msg.sender != escrow) revert OnlyEscrow();
        SafeTransferLib.safeTransfer(token, recipient, amount);
        return true;
    }
}
