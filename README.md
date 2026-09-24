# Liquity V2 in Fe

The Fe implementation now includes the complete pinned contract/interface inventory
and a runnable local deployment. The final integrated suite passes **353 EVM tests
and 64 Fe tests**, including the ABI/size audit.

The target is the complete Liquity V2 contract system, preserving the behavior of
[liquity/bold](https://github.com/liquity/bold), including interest and batch
accounting, liquidation and redistribution, redemptions, stability pools,
collateral branches, authorization, token/NFT behavior, oracle shutdowns, helpers
and zappers. Source mappings and their verification scope are in `port_status.json` and
`governance_status.json`. Governance and connected initiative lifecycles are included.

`reference_manifest.json` pins the Solidity reference and the Fe upstream/master
revision used for the local compiler build. Compiler work is isolated in
`toolchain/fe`; fixes, if needed, will each receive a separate branch, regression
tests and a newsfragment, and be listed in `COMPILER_FIXES.md`.

Initialize pinned sources and build the local compiler:

```sh
python3 scripts/bootstrap.py
```

For an existing checkout, rebuild the compiler with:

```sh
cd toolchain/fe
npm ci --prefix crates/tree-sitter-fe
cargo build --release -p fe --locked
```

Run the current Fe unit tests and Solidity/Fe EVM differential tests from this
repository:

```sh
./scripts/test.sh
```

The math differential suite compares success, return bytes and revert bytes on
the same inputs, with 1,024 fuzz runs per fuzz test plus explicit boundary cases.
The Solidity implementation is imported directly from the pinned reference.

Required completion evidence includes an inventory of implemented interfaces and
contracts, tests against the pinned Solidity contracts, multi-branch end-to-end
deployment and operation, batch changes, liquidation and redemption edge cases,
stability pool compounding/yield, accounting invariants and a reproducible local
deployment command. The local deployment exercises all three branches, all zappers/exchange adapters,
interest batches and all three governance initiatives; see [LOCAL_DEPLOYMENT.md](LOCAL_DEPLOYMENT.md).

Source files retain the corresponding upstream SPDX identifiers. The upstream
Business Source License is in `LICENSE-BUSL-1.1`.

Current verified implementations: LiquityMath, AddressesRegistry, GasPool,
DefaultPool, CollSurplusPool, ActivePool, BoldToken (including ERC20Permit and
EIP712), SortedTroves (including batch operations), TroveNFT, FixedAssetReader, MetadataNFT, AddRemoveManagers, LiquityBase, CollateralRegistry, StabilityPool, TroveManager, BorrowerOperations, the WETH/rETH/wstETH price feeds, HintHelpers, MultiTroveGetter, DebtInFrontHelper and the legacy Constants query contract. The current suite
passes 353 EVM tests plus 64 Fe tests. `PoolSystem.t.sol`
deploys and connects the actual Fe registry, token and pools, and compares
collateral redistribution, surplus claims and interest minting with Solidity.
TroveManagerSystem additionally connects the real manager, pools, token, NFT and
sorted list for liquidation, regular/urgent redemption and shutdown.
BorrowerOperationsSystem connects actual Fe borrowing operations and compares
opening, adjustments, batch management, closing and shutdown against Solidity.
Oracle response sources and collateral tokens are controlled test dependencies.
A connected test uses the actual Fe WETHPriceFeed to trigger the complete
oracle-failure shutdown path through BorrowerOperations and TroveManager.

Use `build/protocol/*.abi.json` for protocol integration after `scripts/test.sh`.
The ABI export validates every function signature, return shape and emitted event
against Solidity. It accounts explicitly for pure implementations of view getters,
the flat seven-value EIP712 domain return, static tuple output metadata,
conservative STATICCALL capability metadata, and unused reference declarations.
Original Fe compiler ABIs remain in `build/*.abi.json`; the audit is recorded in
`tests/results/abi-audit.json`. Runtime parity is checked separately by the EVM tests.

The full source inventory is in `port_status.json` (102 core/helper
source files) and `governance_status.json` (27 governance source files). Pinned
OpenZeppelin, Solady and governance trees are checked for source drift before tests.

SortedTroves tests compare exact list and batch storage, search hints, equal-rate
ordering, access control and stateful randomized operations. TroveNFT tests cover
ERC721 events and approvals, callback rollback and reentrancy, constructor strings,
metadata dependency calls and unpadded transfer calldata. The connected metadata test uses actual Fe TroveNFT, MetadataNFT and FixedAssetReader.
That metadata-specific test uses a manager double. SVG/JSON output matches the reference, including
all image/status variants and pinned production font/logo assets. MetadataNFT creates
a stateless rendering companion in its constructor to satisfy EIP-170; constructor
arguments and protocol ABI remain unchanged. Both runtimes and initcode sizes are checked.

The local compiler is based on upstream/master `f1f89a9dd` with the remaining
pinned fixes documented in [COMPILER_FIXES.md](COMPILER_FIXES.md). The latest
complete protocol checkpoint is `tests/results/complete-port.log` and
`tests/results/complete-port.json` (353 EVM tests and 64 Fe tests).
The packaged deployment smoke passes, and all 150 recorded bytecode files match
the final build exactly; see `tests/results/local-deployment.json` and
[COMPLETION_AUDIT.md](COMPLETION_AUDIT.md). After a successful logged full test run, record its
provenance with `python3 scripts/record_validation.py <log-path>` before edits.

CollateralRegistry tests cover branch allocation, rounding remainders, fallback
to branch debt, partial redemptions, fee decay, malformed constructor arrays and
stateful sequences. A connected test burns actual Fe BOLD and checks rollback
when the redeemer has insufficient tokens. That registry-specific test uses manager doubles.

StabilityPool preserves scale-based P/S/B accounting, pending yield thresholds,
compounding, claims, stashed collateral and the minimum deposit remainder. Tests
include 1,024 sixteen-operation random sequences, scale expiry, arithmetic and
rollback boundaries. StabilityPoolSystem connects actual Fe registry, active and
default pools, StabilityPool and BOLDToken for interest minting, offsets and claims;
the test still drives the BO/TM-side operations.

TroveManager uses three fixed delegate modules to satisfy EIP-170. Its constructor
accepts the registry plus the three module addresses; runtime function selectors
remain unchanged. See [TROVE_MANAGER_DEPLOYMENT.md](TROVE_MANAGER_DEPLOYMENT.md)
for deployment order, ABI metadata and the custom memory-array decoder. The
manager and every module are checked against deployment size limits.

BorrowerOperations also uses three fixed delegate modules, with the registry and
module addresses passed to its constructor. See
[BORROWER_OPERATIONS_DEPLOYMENT.md](BORROWER_OPERATIONS_DEPLOYMENT.md). All public
runtime selectors and the Solidity storage layout are preserved. The historical BorrowerOperations checkpoint is in
`tests/results/borrower-operations.*`; the current full checkpoint is linked above.

The three price feeds retain the original Solidity constructors and public ABI.
Their tests cover normal/redemption prices, strict staleness, malformed answers,
precision errors, shutdown fallback and protection against external-call gas
exhaustion. The price-feed checkpoint is recorded in `tests/results/price-feeds.*`.

HintHelpers and MultiTroveGetter preserve hint sampling, fee calculations, signed
pagination and cursor behavior. Connected tests verify predicted fees against
actual borrowing operations. The historical initiative checkpoint is
`tests/results/initiatives.*`. The separately tested and now locally integrated compiler fix rejects integer
expression literals wider than 256 bits; its branch, regression tests and
newsfragment are documented in [COMPILER_FIXES.md](COMPILER_FIXES.md).

RedemptionHelper supports full simulation, iteration-aware truncation, collateral
minimums and BOLD refunds. Its constructor and public runtime ABI match Solidity;
the explicit memory-array decoder preserves allocation panics and address
validation. A connected test deploys actual Fe CollateralRegistry and verifies
redemption predictions and transfers against Solidity. Common LeftoversSweep
functions also pass differential tests. WETHZapper now supports the complete
native-ETH lifecycle, manager permissions and flash-loan closing. Seven parity
tests and an actual connected protocol lifecycle pass. Its original constructor
arguments are preserved and its deployment sizes are checked by the ABI/size audit. GasCompZapper and both leverage zappers also pass differential and actual
connected protocol tests. Leverage contracts create fixed companions to fit
EVM code-size limits while retaining the original three constructor arguments;
see [ZAPPERS_DEPLOYMENT.md](ZAPPERS_DEPLOYMENT.md). CurveExchange, UniV3Exchange and HybridCurveUniV3Exchange now pass differential
tests, and actual Curve/UniV3 leverage lifecycles are tested on both collateral
branches. UniPriceConverter preserves reference rounding, integer widths and
overflow behavior. Quote helpers and the Balancer flash-loan provider now pass differential tests
and connected leverage lifecycles. Governance is integrated with three fixed modules and connected staking,
voting, bribe, Curve-gauge and Merkl lifecycles. See
[GOVERNANCE_DEPLOYMENT.md](GOVERNANCE_DEPLOYMENT.md) for its extended constructor.
The complete protocol checkpoint includes those paths. Typed interface bindings
and the packaged local runner await the final combined validation.

Run the local system with `python3 tools/local_demo/run.py` after building, or use
`--smoke` for the transaction checks and automatic node shutdown. The runner
uses explicit external development fixtures; protocol contracts are Fe bytecode.
See [LOCAL_DEPLOYMENT.md](LOCAL_DEPLOYMENT.md) for scope and evidence, and
[INTERFACES.md](INTERFACES.md) for reproducible typed interface generation.
