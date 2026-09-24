# TroveManager deployment

The Fe manager uses three fixed delegate modules to stay within EIP-170. The
monolithic implementation exceeded 50 KB even with size-oriented optimization.
The modules execute against the manager's storage and preserve `msg.sender`,
`address(this)`, event emitters, return bytes and revert bytes. There is no upgrade
function or caller-selected delegate target.

Deploy in this order:

1. `TroveOperations()`.
2. `TroveRedemptions()`.
3. `TroveLiquidations(addressesRegistry)` using the branch's registry.
4. `TroveManager(addressesRegistry, operationsModule, redemptionsModule, liquidationsModule)`.

This intentionally extends the Solidity constructor with three module addresses.
All runtime function selectors retain their Solidity signatures. The exported
protocol ABI includes the actual four-argument constructor and the events/errors
emitted by the modules at the manager address. Registry and dependent contracts
must reference the manager, not the modules. Liquidation configuration is read
from the same registry when deploying its module.

The deployment tests enforce the runtime limit on each contract and the initcode
limit including constructor arguments. Main protocol storage slots 0–24 retain
the Solidity layout. Module addresses are immutable and consume no storage slots.

Verified root `-O 1` runtime sizes: manager 10,865 bytes; operations 18,447;
redemptions 18,172; liquidations 12,465. Sizes and artifact hashes are recorded
in `tests/results/abi-audit.json`.

The liquidation entry point uses an explicit selector and a custom `uint256[]`
decoder to preserve Solidity's memory-allocation panic before truncated payload
validation. Fe omits numeric-selector entries from generated ABI metadata; the
ABI exporter adds this tested wire signature explicitly. Raw compiler artifacts
remain available for inspection.

The manager passes differential and connected-system validation. A complete Liquity V2
system also requires BorrowerOperations, price feeds and the remaining helpers
and governance components.
