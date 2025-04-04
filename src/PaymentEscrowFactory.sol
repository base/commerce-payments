// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "./PaymentEscrow.sol";

/// @title PaymentEscrowFactory
/// @notice Factory contract for deploying operator-specific PaymentEscrow instances
/// @author Coinbase
contract PaymentEscrowFactory {
    /// @notice Emitted when a new escrow is created
    /// @param operator The operator address the escrow is bound to
    /// @param escrow The address of the newly created escrow
    event EscrowCreated(address indexed operator, address indexed escrow);

    /// @notice Mapping of operator addresses to their escrow instances
    mapping(address operator => PaymentEscrow escrow) public getOperatorEscrow;

    /// @notice Creates a new PaymentEscrow instance for the caller
    /// @return escrow The address of the newly created escrow
    function createEscrow() external returns (PaymentEscrow escrow) {
        // Ensure operator doesn't already have an escrow
        require(address(getOperatorEscrow[msg.sender]) == address(0), "Operator already has escrow");

        escrow = new PaymentEscrow(msg.sender);

        getOperatorEscrow[msg.sender] = escrow;

        emit EscrowCreated(msg.sender, address(escrow));
    }
}
