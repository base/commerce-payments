# Payment Escrow Protocol

## Overview

The Payment Escrow Protocol is a modular smart contract system designed to facilitate secure commerce payment flows onchain. In traditional payment systems, merchants rely on payment processors to handle the complex flow of funds between buyers and sellers. The Payment Escrow Protocol brings these familiar payment patterns onchain through a secure escrow-based system.

The protocol's core functionality revolves around two key concepts:

- **Authorization**: A commitment of funds for a future payment. When authorized, funds are held in escrow but not yet transferred to the merchant. This is similar to a "hold" on a credit card.
  
- **Capture**: The actual transfer of authorized funds to the merchant. Once funds are authorized, capture is guaranteed to succeed, providing merchants with payment certainty.

## Key Features

### Payment Flows
- **Immediate Capture**: Direct transfer of funds to merchant without escrow period (`charge`)
- **Delayed and partial capture**: Funds held in escrow until fulfillment conditions are met, with support for multiple partial captures (`authorize`, `capture`)
- **Void & Reclaim**: Cancellation of authorized payments with funds returned to buyer (`void`, `reclaim`)
- **Refunds**: Return of captured funds to buyer's wallet (`refund`)

### Other Capabilities
- **Flexible Fee Structure**: Operators can set custom fee rates and fee receiver within a configurable range
- **Authorization Buffers**: Support for payment pre-approval with a higher limit than is ultimately authorized
- **Modular Token Collection**: Extensible system for different payment authorization methods

## Architecture

### Operators

The protocol uses an operator-driven model where designated operators control most aspects of the payment lifecycle apart from reclamation by the payer of expired authorizations. While the protocol itself is permissionless and allows any address to act as an operator, commerce platforms integrating with the protocol can choose to recognize and trust only specific operators.

Operators have the authority to:
- Initiate payment flows using any supported token collector
- Capture authorized funds for merchants
- Void payments that have not yet been captured
- Process refunds
- Set and distribute fees according to configured limits

This model allows commerce platforms to maintain their business logic and payment policies while leveraging the protocol's permissionless onchain infrastructure. For example, a marketplace could act as the operator for all its merchants' payments, ensuring consistent payment processing and fee collection.

### Components

The protocol consists of two main components:

1. **`PaymentEscrow` Contract**: Core contract managing the escrow of funds and payment lifecycle
2. **Token Collectors**: Modular contracts handling different methods of token collection

### Token Collectors
The protocol supports multiple and extensible token collection strategies through specialized collector contracts for both payments and refunds.

 There are two types of collectors:
- Payment collectors handle the initial transfer of funds from buyer to escrow. 
- Refund collectors facilitate the return of funds to buyers by providing refund liquidity

**_A separation of payment and refund collectors prevents the possibility of using residual balances from a payment to cover a refund._**

#### Payment Collectors
- `ERC3009PaymentCollector`: Supports ERC-3009 `receiveWithAuthorization`
- `Permit2PaymentCollector`: Uses Permit2 signatures for gasless approvals
- `PreApprovalPaymentCollector`: Traditional allowance-based collection
- `SpendPermissionPaymentCollector`: Pre-approval with [spend permissions](https://github.com/coinbase/spend-permissions)

#### Refund Collectors
- `OperatorRefundCollector`: Enables operators to provide refund liquidity through standard ERC-20 allowances

This modular collector system allows the protocol to support various token authorization methods while maintaining a consistent interface for the core escrow contract.

## Protocol Invariants

The Payment Escrow Protocol maintains several critical invariants that ensure secure payment flows:

### Payment Flow Sequencing
- Authorization can only be performed before the expiration of the payer's pre-approval
- Capture operations can only occur after successful authorization and before the expiration of the authorization
- Void and reclaim operations require:
  - An existing authorization
  - Some authorized amount remains uncaptured
- Refund operations require:
  - A previous successful capture or immediate charge
  - Refund amount cannot exceed previously captured amount

