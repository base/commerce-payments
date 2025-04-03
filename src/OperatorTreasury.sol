// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title OperatorTreasury
/// @notice Holds funds for a single operator's payments
/// @dev Created by PaymentEscrow to isolate operator funds
contract OperatorTreasury {
    /// @notice The PaymentEscrow contract that created this treasury
    address public immutable escrow;

    /// @notice The operator whose funds this treasury manages
    address public immutable operator;

    error OnlyEscrow();
    error ConfigureAllowanceFailed();
    error TransferFailed();

    constructor(address operator_) {
        escrow = msg.sender; // The escrow deploys this, so it's msg.sender
        operator = operator_;
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
    function sendTokens(address token, uint256 amount, address recipient) external onlyEscrow {
        // Configure allowance for this token if not already set
        _configureAllowance(token);

        // Send tokens to recipient
        bool success = IERC20(token).transfer(recipient, amount);
        if (!success) revert TransferFailed();
    }

    /// @notice Set up infinite allowance to escrow for token if not set
    /// @param token The token to configure allowance for
    function _configureAllowance(address token) internal {
        uint256 allowance = IERC20(token).allowance(address(this), escrow);
        if (allowance != type(uint256).max) {
            // Set infinite approval for escrow
            bool success = IERC20(token).approve(escrow, type(uint256).max);
            if (!success) revert ConfigureAllowanceFailed();
        }
    }
}
