# Commerce Payments Protocol

## Overview

The Commerce Payments Protocol facilitates onchain payments. Specifically designed for authorization and capture patterns, payments are initially collected into an escrow contract to guarantee payment for merchants at a later time. Operators drive token movement through the protocol and can customize their operations with modular smart contracts. No top-level controls exist on the protocol, keeping it permissionless, immutable, inviting of any operators.

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

1. **`AuthCaptureEscrow` Contract**: Core contract managing the escrow of funds and payment lifecycle
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

The Commerce Payments Protocol maintains several critical invariants that ensure secure payment flows:

### Payment Flow Sequencing
- Authorization can only be performed before the expiration of the payer's pre-approval
- Capture operations can only occur after successful authorization and before the expiration of the authorization
- Void and reclaim operations require:
  - An existing authorization
  - Some authorized amount remains uncaptured
- Refund operations require:
  - A previous successful capture or immediate charge
  - Refund amount cannot exceed previously captured amount

## Risks

### Operator compromise

The protocol is designed to limit the scope of damage that can occur in the case that an operator for existing payments is compromised by a malicious actor. Operators cannot steal funds from the protocol. Malicious or inactive operators can censor payments by failing to move a payment through its lifecycle or by prematurely voiding payments. Operators may also have some jurisdiction over how fees behave, depending on how they were configured in the original `PaymentInfo` definition. Operators can apply fees up to the `maxFeeBps` specified in the `PaymentInfo`, and, if the `feeReceiver` was set as `address(0)` in the `PaymentInfo` then this value is dynamically configurable at call time. Therefore in the worst case, an operator could siphon the maximum configurable fee rate to an address of their choosing.

### Denial of service due to denylists

Some tokens, such as USDC, implement denylists that prohibit the movement of funds to or from a blocked address. Due to the atomic nature of transactions onchain, 
if any of the transfers involved in the movement of a payment's funds fail, that step in the payment's lifecycle can't be completed. This is of particular concern for payments
that may have already been authorized, kicking off the fulfillment of a purchase, and cannot later be captured due to a blocked recipient or `feeReceiver`.

Capturing fees may be considered of lesser importance to a given operator than maintaining liveness in the protocol and fulfilling pending payments, making a denylisted `feeReceiver` an unacceptable reason for failing to fulfill payments. We explored design options for mitigating this risk in the core protocol, such as holding failed fee funds in custody for later retrieval, but the complexity of this mechanism wasn't justified by the magnitude of this edge case.

The `feeReceiver` can be a dynamic argument if the `feeReceiver` specified in the `PaymentInfo` is `address(0)`. For operators that care to prioritize liveness of payments over the risk of fees lost due to operator compromise, setting the value of `feeReceiver` to `address(0)` in the initial `PaymentInfo` is a way to mitigate the risk of being permanently unable to fulfill a given payment due to denylists; the operator can simply supply an alternate `feeReceiver` to the `capture` call (for any number of necessary attempts). 