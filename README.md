# Commerce Payments Protocol

A permissionless protocol for onchain payments that mimics traditional "authorize and capture" payment flows.

## Quick Start

The Commerce Payments Protocol facilitates secure escrow-based payments with flexible authorization and capture patterns. Operators drive payment flows using modular token collectors while the protocol ensures payer and merchant protections.

**📖 [Read the Full Documentation](docs/README.md)**

## Key Features

- **Two-Phase Payments**: Separate authorization and capture for guaranteed merchant payments and management of real-world complexity
- **Flexible Fee Structure**: Configurable fee rates and recipients within predefined ranges  
- **Modular Token Collection**: Support for multiple authorization methods (ERC-3009, Permit2, allowances, spend permissions)
- **Built-in Protections**: Time-based expiries, amount limits, and reclaim mechanisms
- **Operator Model**: Permissionless operators manage payment flows while remaining trust-minimized

## Deployment Addresses

### Base Mainnet & Base Sepolia

| Contract | Address |
|----------|---------|
| AuthCaptureEscrow | [`0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff`](https://basescan.org/address/0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff#code) |
| ERC3009PaymentCollector | [`0x0E3dF9510de65469C4518D7843919c0b8C7A7757`](https://basescan.org/address/0x0E3dF9510de65469C4518D7843919c0b8C7A7757#code) |
| Permit2PaymentCollector | [`0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26`](https://basescan.org/address/0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26#code) |
| PreApprovalPaymentCollector | [`0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6`](https://basescan.org/address/0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6#code) |
| SpendPermissionPaymentCollector | [`0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa`](https://basescan.org/address/0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa#code) |
| OperatorRefundCollector | [`0x934907bffd0901b6A21e398B9C53A4A38F02fa5d`](https://basescan.org/address/0x934907bffd0901b6A21e398B9C53A4A38F02fa5d#code) |

## Documentation

- **[Protocol Overview](docs/README.md)** - Architecture, components, and payment lifecycle
- **[Security Analysis](docs/Security.md)** - Security features, risk assessment, and mitigation strategies
- **[Token Collectors Guide](docs/TokenCollectors.md)** - Modular payment authorization methods
- **[Fee System](docs/Fees.md)** - Comprehensive fee mechanics and examples
- **Core Operations:**
  - [Authorize](docs/operations/Authorize.md) - Reserve funds for future capture
  - [Capture](docs/operations/Capture.md) - Transfer authorized funds to merchants  
  - [Charge](docs/operations/Charge.md) - Immediate authorization and capture
  - [Void](docs/operations/Void.md) - Cancel authorizations (operator)
  - [Reclaim](docs/operations/Reclaim.md) - Recover expired authorizations (payer)
  - [Refund](docs/operations/Refund.md) - Return captured funds to payers

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


## Security Audits

Audited by [Spearbit](https://spearbit.com/) and Coinbase Protocol Security.

| Audit | Date | Report |
|--------|---------|---------|
| Coinbase Protocol Security audit 1 | 03/19/2025 | [Report](audits/CommercePaymentsAudit1ProtoSec.pdf) |
| Coinbase Protocol Security audit 2 | 03/26/2025 | [Report](audits/CommercePaymentsAudit2ProtoSec.pdf) |
| Spearbit audit 1 | 04/01/2025 | [Report](audits/Cantina-Report-04-01-2025.pdf) |
| Coinbase Protocol Security audit 3 | 04/15/2025 | [Report](audits/CommercePaymentsAudit3CoinbaseProtoSec.pdf) |
| Spearbit audit 2 | 04/22/2025 | [Report](audits/Cantina-Report-04-22-2025.pdf) |
