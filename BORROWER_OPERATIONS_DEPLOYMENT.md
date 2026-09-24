# BorrowerOperations deployment

The Fe implementation uses three fixed delegate modules to fit the EVM's
24,576-byte runtime limit. The single-contract draft measured 56,519 bytes.
The constructor is intentionally different from Solidity:

```
BorrowerOperations(registry, openingModule, adjustmentsModule, batchesModule)
```

Configure the branch AddressesRegistry first, using predicted addresses where
necessary for circular dependencies. Deploy these modules against that same
configured registry:

1. `BorrowerOpening(registry)` — individual and batch trove opening.
2. `BorrowerAdjustments(registry)` — collateral/debt and individual rate changes.
3. `BorrowerBatches(registry)` — batch registration, rates, joining, removal,
   switching and individual delegate assignment.
4. `BorrowerOperations(registry, opening, adjustments, batches)`.

Each module embeds immutable collateral, WETH, NFT and collateral-ratio
configuration read from the registry. All three must use the same registry and
configuration as the main contract. The main contract keeps the Solidity storage
layout, including the shutdown byte sharing slot 9 with SortedTroves. Module
addresses are immutable: no upgrade function or user-selected delegate target
exists. Delegate calls preserve the original caller and emit events at the main
BorrowerOperations address. Pools, tokens and TroveManager authorize that address.

Closing, pending debt application, shutdown, getters, manager setters and mapping
cleanup execute in the main contract. The exported ABI records the actual
four-address constructor. The companion ABIs are implementation details.

`tests/BorrowerOperationsParity.t.sol` compares calls to the original Solidity
contract. `tests/BorrowerOperationsSystem.t.sol` constructs both connected branch
systems using CREATE2 predictions and exercises user borrowing with the actual
pools, token, NFT, list and TroveManager. Validation results are recorded separately;
this document does not claim completion of the remaining feeds, helpers,
governance or multi-branch deployment work.
