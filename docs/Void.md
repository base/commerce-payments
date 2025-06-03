# Void

The `void` function allows operators to permanently cancel a payment authorization and return escrowed funds to the buyer. This provides a mechanism for operators to reverse authorizations when fulfillment cannot be completed.

## Purpose

Void enables payment cancellation by:
- **Canceling authorizations**: Permanently voids pending payment authorizations
- **Returning escrowed funds**: Transfers all capturable funds back to the buyer
- **Enabling immediate refund**: Void can be called by the payment's operator at any time, even if a payment's authorization has not expired
- **Updating payment state accounting**: Clears the capturable amount for a payment

## How It Works

```solidity
function void(PaymentInfo calldata paymentInfo) 
    external nonReentrant onlySender(paymentInfo.operator)
```

### Process Flow
1. **Authorization Check**: Verifies that capturable funds exist for the payment
2. **State Clearing**: Sets `capturableAmount` to zero permanently
3. **Fund Return**: Transfers all capturable funds back to the original buyer
4. **Event Emission**: Emits `PaymentVoided` for tracking
5. **Permanent Effect**: Payment can never be captured after voiding


## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `paymentInfo` | `PaymentInfo` | Original payment configuration identifying the payment to void |

## Access Control

- **Operator Only**: Only `paymentInfo.operator` can call this function
- **Authorization Required**: Payment must have non-zero `capturableAmount`
- **No Time Restrictions**: Can be called any time before authorization expiry

## State Changes

### Before Void
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 1000e6,  // $1000 USDC authorized
    refundableAmount: 0
}
```

### After Void
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 0,       // Cleared - cannot capture anymore
    refundableAmount: 0        // No refundable amount (funds returned)
}
```

## Events

```solidity
event PaymentVoided(
    bytes32 indexed paymentInfoHash,
    uint256 amount
);
```

Track voided payments for analytics, customer service, and dispute resolution.

## Error Conditions

| Error | Cause |
|-------|--------|
| `InvalidSender` | Caller is not the designated operator |
| `ZeroAuthorization` | Payment has no capturable amount to void |
