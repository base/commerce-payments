// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenStore
///
/// @notice Holds funds for a single operator's payments
///
/// @dev Deployed on demand by AuthCaptureEscrow via CREATE2 clones
///
/// @author Coinbase, Shopify
contract TokenStore {
    /// @notice AuthCaptureEscrow singleton that created this token store
    address public immutable authCaptureEscrow;

    /// @notice Call sender is not AuthCaptureEscrow
    error OnlyAuthCaptureEscrow();

    /// @notice Constructor
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that created this token store
    constructor(address authCaptureEscrow_) {
        authCaptureEscrow = authCaptureEscrow_;
    }

    /// @notice Send tokens to a recipient, called by escrow during capture/refund
    ///
    /// @param token The token being received
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to receive
    ///
    /// @return success True if the transfer was successful
    function sendTokens(address token, address recipient, uint256 amount) external returns (bool) {
        if (msg.sender != authCaptureEscrow) revert OnlyAuthCaptureEscrow();
        SafeERC20.safeTransfer(IERC20(token), recipient, amount);
        return true;
    }
}
