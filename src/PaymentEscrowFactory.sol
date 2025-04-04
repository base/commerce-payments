// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {PaymentEscrow} from "./PaymentEscrow.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";

/// @title PaymentEscrowFactory
/// @notice Factory contract for deploying operator-specific PaymentEscrow instances
/// @author Coinbase
contract PaymentEscrowFactory {
    /// @notice Implementation contract to clone
    PaymentEscrow public immutable implementation;

    /// @notice Emitted when a new escrow is created
    /// @param operator The operator address the escrow is bound to
    /// @param escrow The address of the newly created escrow
    event EscrowCreated(address indexed operator, address indexed escrow);

    /// @notice Mapping of operator addresses to their escrow instances
    mapping(address operator => PaymentEscrow escrow) public getOperatorEscrow;

    constructor() {
        implementation = new PaymentEscrow();
    }

    /// @notice Creates a new PaymentEscrow instance for the caller
    /// @return escrow The address of the newly created escrow
    function createEscrow() external returns (PaymentEscrow escrow) {
        require(address(getOperatorEscrow[msg.sender]) == address(0), "Operator already has escrow");

        // Deploy minimal proxy clone
        escrow = PaymentEscrow(Clones.clone(address(implementation)));

        // Initialize the escrow
        escrow.initialize(msg.sender);

        getOperatorEscrow[msg.sender] = escrow;

        emit EscrowCreated(msg.sender, address(escrow));
    }
}
