// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TokenStore
/// @notice Holds funds for a single operator's payments
/// @dev Created by PaymentEscrow to isolate operator funds
/// @author Coinbase
contract TokenStore {
    /// @notice PaymentEscrow singleton that created this token store
    address public immutable paymentEscrow;

    /// @notice Call sender is not PaymentEscrow
    error OnlyPaymentEscrow();

    /// @notice Constructor
    /// @param paymentEscrow_ PaymentEscrow singleton that created this token store
    constructor(address paymentEscrow_) {
        paymentEscrow = paymentEscrow_;
    }

    /// @notice Send tokens to a recipient, called by escrow during capture/refund
    /// @param token The token being received
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to receive
    function sendTokens(address token, address recipient, uint256 amount) external returns (bool) {
        if (msg.sender != paymentEscrow) revert OnlyPaymentEscrow();
        SafeERC20.safeTransfer(IERC20(token), recipient, amount);
        return true;
    }
}
