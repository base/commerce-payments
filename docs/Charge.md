# Charge

The `charge` function combines authorization and capture into a single atomic operation, immediately transferring funds from buyer to merchant. This provides a streamlined payment flow for scenarios where immediate settlement is desired.

## Purpose

Charge enables direct payment by:
- **Simplifying payment flow**: Combines auth + capture into one transaction
- **Reducing gas costs**: Single transaction instead of two separate calls
- **Immediate settlement**: Funds go directly to merchant without escrow delay
- **Maintaining fee structure**: Still supports fee calculation and distribution
- **Enabling refunds**: Captured amount becomes immediately refundable

## How It Works

```solidity
function charge(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    address tokenCollector,
    bytes calldata collectorData,
    uint16 feeBps,
    address feeReceiver
) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount)
```

### Process Flow
1. **Payment Validation**: Ensures payment info is valid and timing constraints are met
2. **Fee Validation**: Confirms fee parameters are within allowed ranges
3. **Uniqueness Check**: Verifies this payment hasn't already been collected
4. **State Update**: Records payment as collected with `refundableAmount`
5. **Token Collection**: Uses token collector to pull funds from buyer
6. **Fee Distribution**: Immediately distributes funds to merchant and fee recipient
7. **Event Emission**: Emits `PaymentCharged` for tracking

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `paymentInfo` | `PaymentInfo` | Complete payment configuration |
| `amount` | `uint256` | Amount to charge (must be ≤ maxAmount) |
| `tokenCollector` | `address` | Contract that will pull tokens from buyer |
| `collectorData` | `bytes` | Data passed to token collector |
| `feeBps` | `uint16` | Fee percentage in basis points |
| `feeReceiver` | `address` | Address to receive fee portion |

## Access Control

- **Operator Only**: Only `paymentInfo.operator` can call this function
- **Single Use**: Each payment can only be charged once
- **Time Bounded**: Must be called before `preApprovalExpiry`

## State Changes

### Before Charge
```
PaymentState {
    hasCollectedPayment: false,
    capturableAmount: 0,
    refundableAmount: 0
}
```

### After Charge
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 0,         // No capturable amount (already settled)
    refundableAmount: 1000e6     // Full amount immediately refundable
}
```

## Events

```solidity
event PaymentCharged(
    bytes32 indexed paymentInfoHash,
    PaymentInfo paymentInfo,
    uint256 amount,
    address tokenCollector,
    uint16 feeBps,
    address feeReceiver
);
```

The `PaymentCharged` event includes more details than `PaymentCaptured` since it represents the complete payment lifecycle.

## Error Conditions

| Error | Cause |
|-------|--------|
| `InvalidSender` | Caller is not the designated operator |
| `ZeroAmount` | Attempting to charge zero amount |
| `AmountOverflow` | Amount exceeds uint120 maximum |
| `ExceedsMaxAmount` | Amount exceeds paymentInfo.maxAmount |
| `AfterPreApprovalExpiry` | Called after signature expiry |
| `PaymentAlreadyCollected` | Payment already authorized or charged |
| `FeeBpsOutOfRange` | Fee outside min/max range |
| `ZeroFeeReceiver` | Fee recipient is zero address with non-zero fee |
| `InvalidFeeReceiver` | Fee recipient doesn't match payment configuration |
| `InvalidCollectorForOperation` | Wrong collector type used |
| `TokenCollectionFailed` | Token transfer didn't match expected amount |
