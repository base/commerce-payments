# Commerce Payments Protocol

A permissionless protocol for onchain payments that mimics traditional "authorize and capture" payment flows. Built for Base blockchain in collaboration with Shopify to enable onchain express checkout.

## Quick Start

The Commerce Payments Protocol facilitates secure escrow-based payments with flexible authorization and capture patterns. Operators drive payment flows using modular token collectors while the protocol ensures buyer and merchant protections.

**📖 [Read the Full Documentation](docs/Overview.md)**

## Key Features

- **Two-Phase Payments**: Separate authorization and capture for guaranteed merchant payments
- **Flexible Fee Structure**: Configurable fee rates and recipients within predefined ranges  
- **Modular Token Collection**: Support for multiple authorization methods (ERC-3009, Permit2, allowances, spend permissions)
- **Built-in Protections**: Time-based expiries, amount limits, and reclaim mechanisms
- **Operator Model**: Permissionless operators manage payment flows while remaining trust-minimized

## Deployment Addresses

### Base Mainnet & Base Sepolia

| Contract | Address |
|----------|---------|
| AuthCaptureEscrow | `0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff` |
| ERC3009PaymentCollector | `0x0E3dF9510de65469C4518D7843919c0b8C7A7757` |
| Permit2PaymentCollector | `0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26` |
| PreApprovalPaymentCollector | `0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6` |
| SpendPermissionPaymentCollector | `0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa` |
| OperatorRefundCollector | `0x934907bffd0901b6A21e398B9C53A4A38F02fa5d` |

## Documentation

- **[Protocol Overview](docs/Overview.md)** - Architecture, components, and payment lifecycle
- **[Token Collectors Guide](docs/TokenCollectors.md)** - Modular payment authorization methods
- **[Fee System](docs/Fees.md)** - Comprehensive fee mechanics and examples
- **Core Functions:**
  - [Authorize](docs/Authorize.md) - Reserve funds for future capture
  - [Capture](docs/Capture.md) - Transfer authorized funds to merchants  
  - [Charge](docs/Charge.md) - Immediate authorization and capture
  - [Void](docs/Void.md) - Cancel authorizations (operator)
  - [Reclaim](docs/Reclaim.md) - Recover expired authorizations (buyer)
  - [Refund](docs/Refund.md) - Return captured funds to buyers

## Development

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy (example)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- **GitHub Issues**: [commerce-payments repository](https://github.com/base/commerce-payments)
