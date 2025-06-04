
## Security Features

### Payment Validation and Invariants
- **Amount limits**: Enforced via `maxAmount` parameter
- **Time constraints**: Multiple expiry timestamps prevent stale payments
- **Fee validation**: Configurable min/max fee ranges
- **Immutable terms**: All critical parameters signed by buyer, making it enforceable that a given buyer's signature can't be used for a different payment than intended


### Access Control
- **Operator-only**: Most functions restricted to designated operator
- **Buyer reclaim**: Only buyers can reclaim after authorization expiry
- **Collector validation**: Ensures correct collector type for each operation

### Reentrancy Protection
- Uses Solady's `ReentrancyGuard` to protect all public functions from reentrancy

### Liquidity Segementation
- Further protection against unfound bugs by segmenting liquidity held by the escrow into per-operator `TokenStore` vaults, minimizing the risk of any given operator interfering with another operator's liquidity.

### Balance Verification
- Validates exact token amounts transferred to prevent partial payments
- Measures balance changes to ensure collector compliance

## Risks

### Operator compromise
The protocol is designed to limit the scope of damage that can occur in the case that an operator for 
existing payments is compromised by a malicious actor. Operators cannot steal funds from the 
protocol. Malicious or inactive operators can censor payments by failing to move a payment through 
its lifecycle or by prematurely voiding payments. Operators may also have some jurisdiction over how 
fees behave, depending on how they were configured in the original `PaymentInfo` definition. 
Operators can apply fees up to the `maxFeeBps` specified in the `PaymentInfo`, and, if the 
`feeReceiver` was set as `address(0)` in the `PaymentInfo` then this value is dynamically 
configurable at call time. Therefore in the worst case, an operator could siphon the maximum 
configurable fee rate to an address of their choosing.

### Denial of service due to denylists
Some tokens, such as USDC, implement denylists that prohibit the movement of funds to or from a 
blocked address. Due to the atomic nature of transactions onchain, 
if any of the transfers involved in the movement of a payment's funds fail, that step in the 
payment's lifecycle can't be completed. This is of particular concern for payments
that may have already been authorized, kicking off the fulfillment of a purchase, and cannot later be 
captured due to a blocked recipient or `feeReceiver`.
Capturing fees may be considered of lesser importance to a given operator than maintaining liveness 
in the protocol and fulfilling pending payments, making a denylisted `feeReceiver` an unacceptable 
reason for failing to fulfill payments. We explored design options for mitigating this risk in the 
core protocol, such as holding failed fee funds in custody for later retrieval, but the complexity of 
this mechanism wasn't justified by the magnitude of this edge case.

The `feeReceiver` can be a dynamic argument if the `feeReceiver` specified in the `PaymentInfo` is 
`address(0)`. For operators that care to prioritize liveness of payments over the risk of fees lost 
due to operator compromise, setting the value of `feeReceiver` to `address(0)` in the initial 
`PaymentInfo` is a way to mitigate the risk of being permanently unable to fulfill a given payment 
due to denylists; the operator can simply supply an alternate `feeReceiver` to the `capture` call 
(for any number of necessary attempts). 

