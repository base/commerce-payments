# Refund

The `refund` function allows operators to return previously captured funds to buyers. This provides a mechanism for reversing completed payments while maintaining proper accounting. Refunds are limited to the originally captured amount, prevent over-refunding.


Similarly to token collection for payments, modular token collectors are used to source the liquidity for refunds. This enables the implementation of any source of liquidity for refunds. For example, refund liquidity could be held and dispensed directly by the operator, or could be held by the merchant who received the payment and provided to the protocol via a signature-based authorization from that merchant for the specific purpose of refunding a specific payment.

## Purpose

Refund enables payment reversal by:
- **Returning captured funds**: Reverses previously completed payments
- **Preserving payment history**: Maintains records of refund transactions
- **Flexible liquidity sourcing**: Uses refund collectors to securely source funds from arbitrary sources

## How It Works

```solidity
function refund(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    address tokenCollector,
    bytes calldata collectorData
) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount)
```

### Process Flow
1. **Timing Validation**: Ensures refund occurs before `refundExpiry`
2. **Amount Validation**: Confirms refund amount doesn't exceed previously captured funds
3. **State Update**: Decreases `refundableAmount` by refund amount
4. **Token Collection**: Uses refund collector to source refund funds
5. **Fund Transfer**: Transfers refund amount to the original buyer
6. **Event Emission**: Emits `PaymentRefunded` for tracking

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `paymentInfo` | `PaymentInfo` | Original payment configuration |
| `amount` | `uint256` | Amount to refund (must be ≤ refundableAmount) |
| `tokenCollector` | `address` | Refund collector contract to source funds |
| `collectorData` | `bytes` | Data passed to refund collector |

## Access Control

- **Operator Only**: Only `paymentInfo.operator` can call this function
- **Time Bounded**: Must be called before `refundExpiry`
- **Amount Limited**: Cannot exceed available `refundableAmount`

## State Changes

### Before Refund
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 0,
    refundableAmount: 1000e6  // $1000 USDC previously captured
}
```

### After Partial Refund ($300)
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 0,
    refundableAmount: 700e6   // $700 USDC remaining refundable
}
```

## Refund Collectors

Modular refund collectors are used to source the liquidity for refunds. The implemented `OperatorRefundCollector` is a simple example of this, relying on basic ERC-20 approval and sourcing refund liquidity from the operator's balance. Other refund collectors can be implemented that use any payment authorization mechanism to source refund liquidity. For example, an ERC-3009 or Permit2 refund collector could be designed to redeem authorizations from merchants and source liquidity directly from them for the purpose of refunds. 


## Events

```solidity
event PaymentRefunded(
    bytes32 indexed paymentInfoHash,
    uint256 amount,
    address tokenCollector
);
```

Track refunds for accounting, customer service, and dispute resolution.

## Error Conditions

| Error | Cause |
|-------|--------|
| `InvalidSender` | Caller is not the designated operator |
| `ZeroAmount` | Attempting to refund zero amount |
| `AmountOverflow` | Amount exceeds uint120 maximum |
| `AfterRefundExpiry` | Called after refund expiry time |
| `RefundExceedsCapture` | Refund amount exceeds captured amount |
| `InvalidCollectorForOperation` | Wrong collector type used |
| `TokenCollectionFailed` | Refund collector failed to provide funds |
