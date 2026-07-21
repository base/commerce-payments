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
- ✅ `feeAmount: 0, feeReceiver: 0x123...456` (no fee, but the configured recipient must still be supplied)
- ✅ `feeAmount: 25e6, feeReceiver: 0x123...456` (2.5% to fixed recipient)
- ✅ `feeAmount: 100e6, feeReceiver: 0x123...456` (maximum fee)
- ❌ `feeAmount: 25e6, feeReceiver: 0x789...abc` (wrong recipient)
- ❌ `feeAmount: 0, feeReceiver: address(0)` (fixed recipient enforced even when the fee is 0)

> **Note.** When `PaymentInfo.feeReceiver` is a non-zero fixed address, `_validateFee` requires the caller-supplied `feeReceiver` to match it **unconditionally** — including when `feeAmount == 0`. Passing `address(0)` alongside a zero fee against a fixed-recipient payment reverts with `InvalidFeeReceiver`. Receiver matching is only skipped when `PaymentInfo.feeReceiver == address(0)` (flexible recipient), as in Example 3.


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

## Per-Capture Semantics and Rounding

`minFeeBps` and `maxFeeBps` are **per-capture** rate bounds — they are evaluated independently against each `capture()` (or `charge()`) call's `amount`. They are not aggregate, payment-level guarantees over the full authorized amount.

Because the bounds are computed with integer division:

```
minFee = amount * minFeeBps / 10_000
maxFee = amount * maxFeeBps / 10_000
```

both `minFee` and `maxFee` round toward zero. When `amount * minFeeBps < 10_000`, `minFee` rounds to `0` and the operator may supply `feeAmount = 0` for that capture even if `minFeeBps > 0`. Rounding favors the merchant/payer at `maxFee` and favors the operator at `minFee`.

### Fragmentation implication

Because the minimum is per-capture, an operator with capture-amount discretion can, in principle, fragment a large payment into many small captures whose individual `minFee` values each round to zero, reducing the total fee paid below what a single equivalently-sized capture would require. Example: a zero-decimal token authorization of `100` units with `minFeeBps = maxFeeBps = 100` (1%) yields:

- One capture of `100` → `minFee = maxFee = 1` → operator must supply `feeAmount = 1`.
- One hundred captures of `1` each → `minFee = maxFee = 0` → operator may supply `feeAmount = 0` on every one.

This behavior is **pre-existing** — it is a property of per-capture bps-based bounds and integer division, not something introduced by moving the concrete fee amount off-chain. Absolute-fee validation preserves the same per-capture rounding semantics as the previous `feeBps` API.

### Accepted risk

The protocol treats this as an accepted risk under the current operator-trust model:

- Operators are trusted counterparties in the payment flow and, in current deployments, are typically also the fee receiver — fragmenting fees away from themselves has no benefit.
- Per-capture gas costs make fragmenting economically pointless except for low-decimal, high-unit-value tokens.
- Integrators that need aggregate-level fee guarantees should either (a) issue authorizations whose minimum meaningful capture size makes rounding irrelevant, (b) use tokens with sufficient decimals (e.g. USDC's 6 decimals push the rounding gap below one cent for typical bps rates), or (c) constrain operator behavior off-chain.

If a future deployment weakens the operator-trust assumption (for example by allowing arbitrary fee receivers distinct from the operator), integrators should re-evaluate this trade-off. Tightening the guarantee on-chain would require either per-payment aggregate fee accounting or a minimum-capture-size rule, both of which change the two-phase escrow's flexibility and would be handled as separate design work.

The protocol uses integer division which truncates decimals, slightly favoring the merchant in `maxFee` rounding and the operator in `minFee` rounding.

## Event Migration: `topic0` Changes for `PaymentCharged` and `PaymentCaptured`

The absolute-fee migration changed the type of the fee field in both events from `uint16 feeBps` to `uint256 feeAmount`. Solidity derives an event's log `topic0` from `keccak256("EventName(param1,param2,...)")`, so both signature changes produced brand-new `topic0` values. Off-chain indexers filtering by the previous `topic0` will silently observe zero matching logs from any deployment that carries the new signature — no error is raised.

The current mainnet/Sepolia deployment (`0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff`) is immutable and continues to emit the **old** signatures. Any future redeployment of `AuthCaptureEscrow` at a different address will emit the **new** signatures. Consumers migrating across the redeployment boundary must add filters for the new `topic0` values keyed on the new contract address, while continuing to accept the old `topic0` from the existing address for as long as authorizations against it remain in flight.

Additionally, the third `data` field (immediately after `amount`) changes meaning: previously `uint16 feeBps` (right-padded to 32 bytes as a rate in basis points), now `uint256 feeAmount` (an absolute token-unit fee). ABIs from before the migration will decode without error against the new logs but will misinterpret the value (for example, reading a `25e6` USDC fee as `25,000,000 bps`). Integrators must upgrade ABIs alongside the contract address, not lazily.

### Canonical signatures

| Event | Version | Full signature (used to derive `topic0`) |
|---|---|---|
| `PaymentCharged` | old (deployed at `0xBdEA...cff`) | `PaymentCharged(bytes32,(address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,uint16,address)` |
| `PaymentCharged` | new (post-#90) | `PaymentCharged(bytes32,(address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,uint256,address)` |
| `PaymentCaptured` | old (deployed at `0xBdEA...cff`) | `PaymentCaptured(bytes32,uint256,uint16,address)` |
| `PaymentCaptured` | new (post-#90) | `PaymentCaptured(bytes32,uint256,uint256,address)` |

### `topic0` values

| Event | Version | `topic0` |
|---|---|---|
| `PaymentCharged` | old | `0x943ae4341dd799d7aeedc501f616cd26b134639e0bc2ec059581ba3ebbf1e7d0` |
| `PaymentCharged` | new | `0x137b0e73e4453f43c2e1ad2552980a0e0c7e988764619974ca26d37a7159940c` |
| `PaymentCaptured` | old | `0xe749f7bbd01b49bb05abf26ca492cb4dfdea6bedeada8a40fdccd478c73a74e2` |
| `PaymentCaptured` | new | `0xac1e0db1957daedbc6944bcb4c8dc947ff8101d710671ac2ec26309f7f38d58e` |

### Migration checklist for integrators

1. Update ABI JSON alongside the redeployment; do not mix an old ABI with the new contract address.
2. Subscribe to both `topic0` values during any overlap period where authorizations against `0xBdEA...cff` may still capture or refund.
3. Route logs by `(address, topic0)` rather than `topic0` alone; the two signatures will coexist across the two deployed addresses.
4. Confirm all downstream reconciliation, monitoring, and dashboarding pipelines have been redeployed with the new ABI before the new address begins receiving production traffic.
