# Fee System

The Commerce Payments Protocol implements a fee system that provides flexibility while maintaining security through pre-defined constraints. Fee bounds are specified in the initial `PaymentInfo` struct (via `minFeeBps`/`maxFeeBps`), while the concrete absolute `feeAmount` is supplied and validated during `charge()` and `capture()` operations.

## Overview

The operator supplies the fee at capture/charge time as an **absolute `feeAmount` denominated in raw token units** — it is no longer expressed in basis points. The `PaymentInfo` struct still bounds the allowable fee using basis points (`minFeeBps`/`maxFeeBps`, where 10,000 basis points = 100%), and the protocol validates that the provided `feeAmount` falls within the bounds those rates imply for the given capture/charge `amount`:

```
minFee = amount * minFeeBps / 10000
maxFee = amount * maxFeeBps / 10000
require(minFee <= feeAmount <= maxFee)
```

For example, capturing `1000e6` USDC with `minFeeBps = maxFeeBps = 250` (2.5%) requires `feeAmount == 25e6` (25 USDC).

## Fee Parameters in `PaymentInfo`

Three parameters in the `PaymentInfo` struct control fee behavior:

```solidity
struct PaymentInfo {
    // ... other fields ...
    uint16 minFeeBps;    // Minimum allowed fee rate
    uint16 maxFeeBps;    // Maximum allowed fee rate  
    address feeReceiver; // Fee recipient (0 = flexible)
    // ... other fields ...
}
```

### Fee Rate Range (`minFeeBps` and `maxFeeBps`)

These parameters bound the allowed absolute fee for the payment (applied to the capture/charge `amount`):

- **Fixed Rate**: When `minFeeBps == maxFeeBps`, the operator must supply exactly `amount * feeBps / 10000` token units
- **Variable Rate**: When `minFeeBps < maxFeeBps`, the operator can supply any `feeAmount` between the two implied bounds
- **Zero Fees**: When both are 0, the only valid `feeAmount` is 0

### Fee Receiver (`feeReceiver`)

Controls who can receive the fee portion:

- **Fixed Recipient**: When set to a specific address, all fees must go to that address
- **Flexible Recipient**: When set to `address(0)`, the operator can specify any fee receiver during capture/charge

## Fee Validation Rules

During `charge()` and `capture()` operations, the protocol validates:

1. **Fee Bounds**: `amount * minFeeBps / 10000 ≤ feeAmount ≤ amount * maxFeeBps / 10000`
2. **Maximum Limit**: `maxFeeBps ≤ 10,000` (cannot exceed 100%)
3. **Range Validity**: `minFeeBps ≤ maxFeeBps`
4. **Zero Fee Receiver**: If `feeAmount > 0`, then `feeReceiver` cannot be `address(0)`
5. **Fixed Recipient**: If `PaymentInfo.feeReceiver != address(0)`, the provided `feeReceiver` must match exactly

## Fee Distribution

When fees are applied:

1. **Fee Amount**: The operator-supplied absolute `feeAmount` (already validated against the bounds above)
2. **Fee Transfer**: If `feeAmount > 0`, transfer to `feeReceiver`
3. **Remaining Transfer**: Transfer `amount - feeAmount` to the merchant (`receiver`)

## Examples

### Example 1: Fixed Fee Rate with Fixed Recipient

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 250,           // 2.5%
    maxFeeBps: 250,           // 2.5% (same as min = fixed rate)
    feeReceiver: 0x123...456  // Specific fee recipient
});
```

**Operator Options at Capture/Charge (for a `1000e6` capture ⇒ bounds are exactly `25e6`):**
- ✅ `feeAmount: 25e6, feeReceiver: 0x123...456` 
- ❌ `feeAmount: 30e6, feeReceiver: 0x123...456` (exceeds max)
- ❌ `feeAmount: 25e6, feeReceiver: 0x789...abc` (wrong recipient)


### Example 2: Variable Fee Rate with Flexible Recipient

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 100,          // 1.0% minimum
    maxFeeBps: 500,          // 5.0% maximum
    feeReceiver: address(0)  // Flexible recipient
});
```

**Operator Options at Capture/Charge (for a `1000e6` capture ⇒ bounds are `10e6`–`50e6`):**
- ✅ `feeAmount: 10e6, feeReceiver: 0x123...456` (minimum)
- ✅ `feeAmount: 35e6, feeReceiver: 0x789...abc` (mid-range)
- ✅ `feeAmount: 50e6, feeReceiver: 0xdef...123` (maximum)
- ❌ `feeAmount: 5e6, feeReceiver: 0x123...456` (below minimum)
- ❌ `feeAmount: 60e6, feeReceiver: 0x123...456` (exceeds maximum)
- ❌ `feeAmount: 30e6, feeReceiver: address(0)` (zero fee receiver with non-zero fee)

**Use Case**: Marketplace with tiered fee structure based on merchant volume

### Example 3: Zero Fees Only

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 0,            // 0%
    maxFeeBps: 0,            // 0% (no fees allowed)
    feeReceiver: address(0)  // Not used since no fees
});
```

**Operator Options at Capture/Charge:**
- ✅ `feeAmount: 0, feeReceiver: address(0)`
- ✅ `feeAmount: 0, feeReceiver: 0x123...456` (fee receiver ignored when fee is 0)
- ❌ `feeAmount: 1, feeReceiver: 0x123...456` (any non-zero fee rejected)


### Example 4: Flexible Rate with Fixed Recipient

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 0,             // 0% minimum (fees optional)
    maxFeeBps: 1000,          // 10% maximum
    feeReceiver: 0x123...456  // Fixed recipient
});
```

**Operator Options at Capture/Charge (for a `1000e6` capture ⇒ bounds are `0`–`100e6`):**
- ✅ `feeAmount: 0, feeReceiver: address(0)` (no fee, receiver ignored)
- ✅ `feeAmount: 25e6, feeReceiver: 0x123...456` (2.5% to fixed recipient)
- ✅ `feeAmount: 100e6, feeReceiver: 0x123...456` (maximum fee)
- ❌ `feeAmount: 25e6, feeReceiver: 0x789...abc` (wrong recipient)


## Multiple Captures with Different Fees

For partial captures, operators can supply different fee amounts, each validated against the bounds implied by that capture's `amount`:

```solidity
// Initial authorization: 1000 USDC
// PaymentInfo: minFeeBps=200, maxFeeBps=400, feeReceiver=address(0)

// First capture: 600 USDC, 12 USDC fee (2% of 600, within 12e6-24e6 bounds)
capture(paymentInfo, 600e6, 12e6, feeRecipient1);
// Fee: 12 USDC to feeRecipient1, 588 USDC to merchant

// Second capture: 400 USDC, 16 USDC fee (4% of 400, within 8e6-16e6 bounds)
capture(paymentInfo, 400e6, 16e6, feeRecipient2);
// Fee: 16 USDC to feeRecipient2, 384 USDC to merchant
```

## Error Conditions

The protocol will revert with specific errors for invalid fee configurations:

| Error | Condition | Example |
|-------|-----------|---------|
| `FeeBpsOverflow` | `maxFeeBps > 10000` | Setting 150% fee rate |
| `InvalidFeeBpsRange` | `minFeeBps > maxFeeBps` | min=500, max=200 |
| `FeeAmountOutOfRange` | `feeAmount` outside bounds implied by min/max fee bps | `30e6` fee when bounds are `50e6`–`100e6` |
| `ZeroFeeReceiver` | Non-zero fee with zero recipient | `25e6` fee, address(0) recipient |
| `InvalidFeeReceiver` | Wrong recipient for fixed fee | Different address than PaymentInfo.feeReceiver |

The protocol uses integer division which truncates decimals, slightly favoring the merchant in rounding scenarios.
