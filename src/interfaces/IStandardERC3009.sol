// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @title IStandardERC3009
/// @notice Interface for the standard version of ERC3009's receiveWithAuthorization
/// @dev This version uses v, r, s components instead of packed signature bytes
interface IStandardERC3009 {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
