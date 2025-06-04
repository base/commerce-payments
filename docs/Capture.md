# Capture

The `capture` function transfers previously authorized funds from escrow to the merchant and fee recipient. This completes the "capture" phase of the two-phase payment pattern.

## Purpose

Capture finalizes the payment by:
- **Transferring funds to merchant**: Moves escrowed funds to the designated receiver
- **Processing fees**: Automatically calculates and distributes fees to the specified recipient
- **Updating payment state**: Converts capturable amount to refundable amount
- **Enabling partial settlement**: Allows capturing authorized funds in multiple increments
- **Maintaining merchant guarantees**: Ensures authorized funds are available for capture until expiry

## How It Works

```solidity
function capture(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    uint16 feeBps,
    address feeReceiver
) external nonReentrant onlySender(paymentInfo.operator) validAmount(amount)
```

### Process Flow
1. **Fee Validation**: Ensures fee parameters are within allowed ranges and recipient is valid (see [Fees](Fees.md))
2. **Timing Check**: Verifies capture occurs before authorization expiry
3. **Availability Check**: Confirms sufficient authorized funds are available
4. **State Update**: Reduces `capturableAmount` and increases `refundableAmount` by captured `amount`
5. **Fee Calculation**: Calculates fee amount based on basis points
6. **Token Distribution**: Transfers fee to recipient and remaining amount to merchant
7. **Event Emission**: Emits `PaymentCaptured` for tracking

### Key Validations
- Must be called before `paymentInfo.authorizationExpiry`
- `amount` cannot exceed available `capturableAmount`
- `feeBps` must be within `[paymentInfo.minFeeBps, paymentInfo.maxFeeBps]` range
- `feeReceiver` must match `paymentInfo.feeReceiver` if specified

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `paymentInfo` | `PaymentInfo` | Original payment configuration |
| `amount` | `uint256` | Amount to capture from escrow |
| `feeBps` | `uint16` | Fee percentage in basis points (0-10000) |
| `feeReceiver` | `address` | Address to receive fee portion |

## Access Control

- **Operator Only**: Only `paymentInfo.operator` can call this function
- **Time Bounded**: Must be called before `authorizationExpiry`
- **Amount Limited**: Cannot exceed currently available `capturableAmount`

## State Changes

### Before Capture
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 1000e6, // $1000 USDC authorized
    refundableAmount: 0
}
```

### After Capture ($500)
```
PaymentState {
    hasCollectedPayment: true,
    capturableAmount: 500e6,  // $500 USDC remaining
    refundableAmount: 500e6   // $500 USDC now refundable
}
```

## Events

```solidity
event PaymentCaptured(
    bytes32 indexed paymentInfoHash,
    uint256 amount,
    uint16 feeBps,
    address feeReceiver
);
```

Track captures to monitor payment settlement and fee distribution.

## Error Conditions

| Error | Cause |
|-------|--------|
| `InvalidSender` | Caller is not the designated operator |
| `ZeroAmount` | Attempting to capture zero amount |
| `AmountOverflow` | Amount exceeds uint120 maximum |
| `FeeBpsOutOfRange` | Fee outside min/max range |
| `ZeroFeeReceiver` | Fee recipient is zero address with non-zero fee |
| `InvalidFeeReceiver` | Fee recipient doesn't match payment configuration |
| `AfterAuthorizationExpiry` | Called after authorization expired |
| `InsufficientAuthorization` | Amount exceeds available capturable balance |

