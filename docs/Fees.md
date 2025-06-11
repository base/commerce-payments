# Fee System

The Commerce Payments Protocol implements a fee system that provides flexibility while maintaining security through pre-defined constraints. Fees are specified in the initial `PaymentInfo` struct and validated during `charge()` and `capture()` operations.

## Overview

Fees in the protocol are calculated as **basis points** (bps), where 10,000 basis points = 100%. For example:
- 250 bps = 2.5%
- 1000 bps = 10.0%

The fee amount is calculated as: `feeAmount = totalAmount * feeBps / 10000`

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

These parameters establish the allowed fee range for the payment:

- **Fixed Rate**: When `minFeeBps == maxFeeBps`, the operator must use exactly that fee rate
- **Variable Rate**: When `minFeeBps < maxFeeBps`, the operator can choose any rate within the range
- **Zero Fees**: When both are 0, no fees can be charged

### Fee Receiver (`feeReceiver`)

Controls who can receive the fee portion:

- **Fixed Recipient**: When set to a specific address, all fees must go to that address
- **Flexible Recipient**: When set to `address(0)`, the operator can specify any fee receiver during capture/charge

## Fee Validation Rules

During `charge()` and `capture()` operations, the protocol validates:

1. **Rate Range**: `minFeeBps ≤ feeBps ≤ maxFeeBps`
2. **Maximum Limit**: `maxFeeBps ≤ 10,000` (cannot exceed 100%)
3. **Range Validity**: `minFeeBps ≤ maxFeeBps`
4. **Zero Fee Receiver**: If `feeBps > 0`, then `feeReceiver` cannot be `address(0)`
5. **Fixed Recipient**: If `PaymentInfo.feeReceiver != address(0)`, the provided `feeReceiver` must match exactly

## Fee Distribution

When fees are applied:

1. **Fee Calculation**: `feeAmount = amount * feeBps / 10000`
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

**Operator Options at Capture/Charge:**
- ✅ `feeBps: 250, feeReceiver: 0x123...456` 
- ❌ `feeBps: 300, feeReceiver: 0x123...456` (exceeds max rate)
- ❌ `feeBps: 250, feeReceiver: 0x789...abc` (wrong recipient)


### Example 2: Variable Fee Rate with Flexible Recipient

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 100,          // 1.0% minimum
    maxFeeBps: 500,          // 5.0% maximum
    feeReceiver: address(0)  // Flexible recipient
});
```

**Operator Options at Capture/Charge:**
- ✅ `feeBps: 100, feeReceiver: 0x123...456` (minimum rate)
- ✅ `feeBps: 350, feeReceiver: 0x789...abc` (mid-range rate)
- ✅ `feeBps: 500, feeReceiver: 0xdef...123` (maximum rate)
- ❌ `feeBps: 50, feeReceiver: 0x123...456` (below minimum)
- ❌ `feeBps: 600, feeReceiver: 0x123...456` (exceeds maximum)
- ❌ `feeBps: 300, feeReceiver: address(0)` (zero fee receiver with non-zero fee)

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
- ✅ `feeBps: 0, feeReceiver: address(0)`
- ✅ `feeBps: 0, feeReceiver: 0x123...456` (fee receiver ignored when fee is 0)
- ❌ `feeBps: 1, feeReceiver: 0x123...456` (any non-zero fee rejected)


### Example 4: Flexible Rate with Fixed Recipient

```solidity
PaymentInfo memory payment = PaymentInfo({
    // ... other fields ...
    minFeeBps: 0,             // 0% minimum (fees optional)
    maxFeeBps: 1000,          // 10% maximum
    feeReceiver: 0x123...456  // Fixed recipient
});
```

**Operator Options at Capture/Charge:**
- ✅ `feeBps: 0, feeReceiver: address(0)` (no fee, receiver ignored)
- ✅ `feeBps: 250, feeReceiver: 0x123...456` (2.5% to fixed recipient)
- ✅ `feeBps: 1000, feeReceiver: 0x123...456` (maximum fee)
- ❌ `feeBps: 250, feeReceiver: 0x789...abc` (wrong recipient)


## Multiple Captures with Different Fees

For partial captures, operators can use different fee rates within the allowed range:

```solidity
// Initial authorization: 1000 USDC
// PaymentInfo: minFeeBps=200, maxFeeBps=400, feeReceiver=address(0)

// First capture: 600 USDC at 2% fee
capture(paymentInfo, 600e6, 200, feeRecipient1);
// Fee: 12 USDC to feeRecipient1, 588 USDC to merchant

// Second capture: 400 USDC at 4% fee  
capture(paymentInfo, 400e6, 400, feeRecipient2);
// Fee: 16 USDC to feeRecipient2, 384 USDC to merchant
```

## Error Conditions

The protocol will revert with specific errors for invalid fee configurations:

| Error | Condition | Example |
|-------|-----------|---------|
| `FeeBpsOverflow` | `maxFeeBps > 10000` | Setting 150% fee rate |
| `InvalidFeeBpsRange` | `minFeeBps > maxFeeBps` | min=500, max=200 |
| `FeeBpsOutOfRange` | Fee outside allowed range | 300 bps when range is 500-1000 |
| `ZeroFeeReceiver` | Non-zero fee with zero recipient | 250 bps fee, address(0) recipient |
| `InvalidFeeReceiver` | Wrong recipient for fixed fee | Different address than PaymentInfo.feeReceiver |

The protocol uses integer division which truncates decimals, slightly favoring the merchant in rounding scenarios.
