# Commerce Payments Protocol
## Overview

The Commerce Payments Protocol facilitates onchain payments. Traditional payment flows typically involve a multi-step "authorize and capture" pattern where payments are initially collected into an escrow contract to guarantee payment for merchants at a later time. This payment lifecycle helps facilitate the management of race conditions that can occur between checkout completion, payment processing, and actual order fulfillment (for example, inventory selling out, tax burdens changing, gift card balances being spent, etc.). The Commerce Payments Protocol is a permissionless, immutable mechanism designed to securely facilitate the multi-step lifecycle of real-world payments.

Permissionless operators drive token movement through the protocol and can customize their operations with modular smart contracts. No top-level controls exist on the protocol, keeping it permissionless, immutable and usable by any operator.



The protocol's core functionality revolves around two key concepts:

- **Authorization**: A commitment of funds for a future payment. When authorized, funds are held in escrow but not yet transferred to the merchant. This is similar to a "hold" on a credit card.
  
- **Capture**: Funds are transferred from escrow to merchants after fulfillment or other conditions ar met. Capture is guaranteed to succeed if funds have been authorized, providing merchants with payment certainty.


This pattern ensures that successful authorization always leads to successful capture, providing merchants with payment guarantees while maintaining buyer protections.

## Architecture
TODO DIAGRAM

#### 1. `AuthCaptureEscrow`
The main escrow contract that manages funds and payment lifecycle:
- Validates payment parameters and timing constraints
- Manages payment state (authorized, captured, refunded)
- Handles fee distribution
- Ensures atomic operations with reentrancy protection

#### 2. Token Collectors
Pluggable payment modules that handle different authorization methods. See the complete [Token Collectors Guide](TokenCollectors.md) for detailed information on each collector type:
- **ERC3009PaymentCollector**: Uses ERC-3009 `receiveWithAuthorization` signatures
- **Permit2PaymentCollector**: Uses Permit2 signature-based transfers
- **PreApprovalPaymentCollector**: Uses traditional ERC-20 allowances with pre-approval
- **SpendPermissionPaymentCollector**: Uses Coinbase's Spend Permission system
- **OperatorRefundCollector**: Handles refunds from operator funds

#### 3. TokenStore
Per-operator token vaults that hold escrowed funds:
- Deployed deterministically using CREATE2
- Isolated storage per operator for security
- Minimal proxy pattern for gas efficiency

## Core Functions

The protocol provides six main functions that handle the complete payment lifecycle:

### Payment Initiation
- **[Authorize](Authorize.md)** - Reserve buyer funds in escrow for future capture. Enables delayed settlement while guaranteeing merchant payment upon successful authorization.

- **[Charge](Charge.md)** - Combine authorization and capture into a single transaction for immediate payment settlement. Ideal for digital goods and low-risk transactions.

### Payment Settlement  
- **[Capture](Capture.md)** - Transfer previously authorized funds from escrow to merchants. Supports partial captures and flexible fee distribution.

### Payment Cancellation
- **[Void](Void.md)** - Cancel payment authorizations and return escrowed funds to buyers. Operator-initiated for business cancellations and risk management.

- **[Reclaim](Reclaim.md)** - Allow buyers to recover funds from expired authorizations. Buyer-initiated safety mechanism after authorization expiry.

### Payment Reversal
- **[Refund](Refund.md)** - Return previously captured funds to buyers using modular refund collectors. Supports partial refunds and flexible liquidity sourcing.


## Payment Info Structure

Every payment is defined by a `PaymentInfo` struct containing immutable terms:

```solidity
struct PaymentInfo {
    address operator;           // Entity managing the payment flow (e.g., Shopify)
    address payer;             // Buyer's wallet address
    address receiver;          // Merchant's receiving address
    address token;             // Payment token contract
    uint120 maxAmount;         // Maximum amount that can be authorized
    uint48 preApprovalExpiry;  // When buyer's signature expires
    uint48 authorizationExpiry; // When auth can no longer be captured
    uint48 refundExpiry;       // When refunds are no longer allowed
    uint16 minFeeBps;          // Minimum fee in basis points
    uint16 maxFeeBps;          // Maximum fee in basis points
    address feeReceiver;       // Fee recipient (0 = operator sets at capture)
    uint256 salt;              // Entropy for unique payment identification
}
```



## Security Features

### Payment Validation
- **Amount limits**: Enforced via `maxAmount` parameter
- **Time constraints**: Multiple expiry timestamps prevent stale payments
- **Fee validation**: Configurable min/max fee ranges
- **Immutable terms**: All critical parameters signed by buyer

### Access Control
- **Operator-only**: Most functions restricted to designated operator
- **Buyer reclaim**: Only buyers can reclaim after authorization expiry
- **Collector validation**: Ensures correct collector type for each operation

### Reentrancy Protection
- Uses Solady's `ReentrancyGuardTransient` for gas efficiency
- Protects against cross-function and cross-contract reentrancy

### Balance Verification
- Validates exact token amounts transferred to prevent partial payments
- Measures balance changes to ensure collector compliance

## Fee Structure

Flexible fee system supporting various business models:

- **Basis points**: Fees specified as portions of 10,000 (e.g., 250 = 2.5%)
- **Dynamic recipients**: Fee receiver can be set per payment or at capture time
- **Range validation**: Min/max fee bounds prevent fee manipulation
- **Zero-fee support**: Explicitly supports zero-fee transactions

Common patterns:
- **Processing fees**: Baseline fees for payment processing
- **Referral fees**: Additional fees for referral partners  
- **Promotional pricing**: Reduced or waived fees for specific merchants/buyers


## Monitoring and Events

Key events for payment tracking:
- `PaymentAuthorized`: Funds escrowed successfully
- `PaymentCharged`: Immediate charge completed
- `PaymentCaptured`: Funds transferred to merchant
- `PaymentVoided`: Authorization cancelled by operator
- `PaymentReclaimed`: Funds reclaimed by buyer
- `PaymentRefunded`: Refund processed

## Deployment Addresses

TODO list actual deployed addresses


The contracts support deterministic deployment across chains using CREATE2:

| Contract | Description |
|----------|-------------|
| AuthCaptureEscrow | Main escrow contract |
| ERC3009PaymentCollector | ERC-3009 signature collector |
| Permit2PaymentCollector | Permit2 universal collector |
| PreApprovalPaymentCollector | Traditional allowance collector |
| SpendPermissionPaymentCollector | Spend Permission collector |
| OperatorRefundCollector | Operator refund collector |

## Known Dependencies

- **Multicall3**: `0xcA11bde05977b3631167028862bE2a173976CA11`
- **Permit2**: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
- **Spend Permission Manager**: `0xf85210B21cC50302F477BA56686d2019dC9b67Ad`

## Support

For integration support and questions:
- GitHub Issues: [commerce-payments repository](https://github.com/base/commerce-payments)
- Documentation: [Base Documentation](https://docs.base.org) 