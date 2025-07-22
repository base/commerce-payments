# Commerce Payments Protocol

## Project Overview

The Commerce Payments Protocol is a permissionless protocol for onchain payments that mimics traditional "authorize and capture" payment flows. It facilitates secure escrow-based payments with flexible authorization and capture patterns, similar to how traditional payment processors like Stripe handle two-phase transactions.

## Key Concepts

### Core Components
- **AuthCaptureEscrow**: Main escrow contract that handles payment lifecycle
- **TokenCollectors**: Modular components for different authorization methods (ERC-3009, Permit2, allowances, spend permissions)
- **TokenStore**: Contract that manages escrowed funds
- **Operators**: Permissionless entities that drive payment flows while remaining trust-minimized

### Payment Operations
- **Authorize**: Reserve funds for future capture (like a hold on a credit card)
- **Capture**: Transfer authorized funds to merchants
- **Charge**: Immediate authorization and capture in one transaction
- **Void**: Cancel authorizations (operator action)
- **Reclaim**: Recover expired authorizations (payer action)
- **Refund**: Return captured funds to payers

### Architecture
The protocol uses a two-phase payment model:
1. **Authorization Phase**: Funds are escrowed from payer with operator's permission
2. **Capture Phase**: Escrowed funds are distributed to merchant and fee recipients

## Development Environment

This is a **Foundry-based Solidity project** with the following structure:
- `src/`: Smart contracts
- `test/`: Test files
- `script/`: Deployment scripts
- `docs/`: Documentation
- `lib/`: Dependencies (git submodules)

## Development Commands

### Setup
```bash
# Install dependencies
forge install

# Update dependencies
forge update
```

### Testing
```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/src/PaymentEscrow/authorize.t.sol

# Run tests with gas reports
forge test --gas-report
```

### Building
```bash
# Build contracts
forge build

# Build with size information
forge build --sizes

# Build with specific profile
FOUNDRY_PROFILE=deploy forge build
```

### Code Quality
```bash
# Format code
forge fmt

# Check formatting
forge fmt --check
```

### Deployment
```bash
# Deploy to network (example)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast

# Deploy with verification
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Current Deployments

### Base Mainnet & Base Sepolia
- **AuthCaptureEscrow**: `0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff`
- **ERC3009PaymentCollector**: `0x0E3dF9510de65469C4518D7843919c0b8C7A7757`
- **Permit2PaymentCollector**: `0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26`
- **PreApprovalPaymentCollector**: `0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6`
- **SpendPermissionPaymentCollector**: `0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa`
- **OperatorRefundCollector**: `0x934907bffd0901b6A21e398B9C53A4A38F02fa5d`

## Security

The protocol has been audited by:
- **Spearbit** (2 audits)
- **Coinbase Protocol Security** (3 audits)

All audit reports are available in the `audits/` directory.

## Key Dependencies

- **Foundry**: Build tool and testing framework
- **OpenZeppelin Contracts**: Standard contract implementations
- **Solady**: Gas-optimized utility libraries
- **Permit2**: Advanced token permission system
- **Spend Permissions**: Account abstraction spending framework

## Documentation Structure

- `docs/README.md`: Protocol overview and architecture
- `docs/Security.md`: Security analysis and risk assessment
- `docs/TokenCollectors.md`: Guide to modular payment authorization
- `docs/Fees.md`: Fee system mechanics
- `docs/operations/`: Detailed operation guides

## Contributing Notes

- Follow existing code style and patterns
- All contracts use Solidity ^0.8.28
- Use descriptive commit messages
- Ensure tests pass before submitting PRs
- Consider gas optimization in implementations
- Security is paramount - all changes should be carefully reviewed

## Environment Variables

Common environment variables used in scripts:
- `BASE_RPC_URL`: RPC endpoint for Base network
- `SENDER`: Deployer address
- `BASESCAN_API_KEY`: API key for contract verification

## Foundry Profiles

- `default`: Standard development settings
- `deploy`: Optimized for production deployment (via_ir, high optimizer runs)
- `ci`: Continuous integration settings