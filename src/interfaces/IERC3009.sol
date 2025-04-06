// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @dev ERC-3009 does not actually support this method, but it should.
/// @dev We should use this opportunity to change the standard to use generic signatures this time.
/// @dev USDC and EURC use this interface without it being an official standard yet.
/// @dev Reverts if signature validation fails.
interface IERC3009 {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external;

    // Optional but useful for checking if an authorization has been used
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
