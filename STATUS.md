# Current work state

The complete Liquity V2 port goal remains active. The verified contracts below
are a partial system; remaining library/interface coverage, governance and
complete multi-branch workflows are still outstanding.

## Validated checkpoint

`./scripts/test.sh` passes **291 EVM tests and 2 Fe tests**, with 1,024 runs per
fuzz test plus cached regression inputs. Sources, scripts, tests, artifacts,
compiler and reference hashes are recorded in `tests/results/initiatives.json`;
the complete log is `tests/results/initiatives.log`.

Implemented and differentially tested:
- LiquityMath and protocol constants.
- AddressesRegistry and GasPool.
- DefaultPool, CollSurplusPool and ActivePool, including interest, batch fees,
  shutdown, transfers, permissions and rollback.
- BoldToken: ERC20, permits, EIP712 and branch/registry permissions.
- SortedTroves: individual and batch operations, hint search and exact storage.
- TroveNFT: ERC721, callbacks/reentrancy, metadata, malformed/unpadded ABI inputs.
- FixedAssetReader: SSTORE2 clipping, cap, empty/invalid pointers and packed assets.
- MetadataNFT: exact nested base64 JSON/SVG, numeric formatting, checksummed owner,
  all Bauhaus/status variants, arbitrary token strings and production assets.
- CollateralRegistry: all branches, fallback allocation, fee decay, exact rounding,
  partial redemptions and real BOLD burn/rollback; 11 differential tests include
  1,024 random sequences of 12 redemptions each.
- StabilityPool: exact P/S/B and scale accounting, pending rewards, compounding,
  stash/claim behavior, minimum remainder and rollback. Ten parity tests plus one
  system test; fuzz includes 1,024 sixteen-operation sequences and reward arithmetic.
- TroveManager: public getters, all borrower/batch hooks, liquidation, redistribution,
  regular/urgent redemption, zombie handling and shutdown. Fixed delegate modules
  preserve manager storage, caller and events; the constructor adds module addresses.
  See TROVE_MANAGER_DEPLOYMENT.md. Tests include three memory-array ABI tests,
  12 data/state tests, eight hook tests, ten flow tests and a real connected system.
- BorrowerOperations: opening, collateral/debt adjustments, repayment caps,
  closing, pending debt, delegation, batch registration/rates/migration,
  fee checks and shutdown. Twelve differential tests and two connected-system
  tests cover the full public interface, storage, logs, rollback and ABI failures.
  Fixed module deployment is documented in BORROWER_OPERATIONS_DEPLOYMENT.md.
- WETHPriceFeed, RETHPriceFeed and WSTETHPriceFeed: primary/redemption pricing,
  exact deviation boundaries, precision/staleness validation, oracle failure
  priority, monotonic shutdown fallback, malformed responses and out-of-gas
  protection. Twelve parity tests and an actual connected oracle-shutdown test
  pass. Runtime sizes: 1,102, 2,542 and 2,538 bytes respectively.
- HintHelpers and MultiTroveGetter: probabilistic hints, all fee predictions,
  signed pagination, complete trove records and debt-by-rate traversal. Six
  differential tests and a connected test compare predictions with actual
  opening, rate changes and batch joining.
- DebtInFrontHelper: bounded debt ranges, excluded/stop-at troves, hint selection,
  signed-overflow behavior, and connected debt-in-front queries. The legacy
  Constants query contract is also implemented and ABI-checked.
- RedemptionHelper: full simulation, debt-based fallback allocation, iteration
  truncation, redemption-price fetching, minimum-collateral checks and BOLD refunds.
  Nine differential tests and one actual-registry system test cover storage,
  malformed ABI, dependency failures and rollback. Runtime: 9,835 bytes.
- LeftoversSweep: common zapper balance snapshots and surplus returns, with three
  parity tests including 1,024 fuzz runs.
- WETHZapper: native ETH opening, adjustments, closing, flash-loan closing,
  manager permissions and surplus handling. Seven parity tests plus a connected
  lifecycle test pass; runtime 19,470 bytes, original constructor arguments.
  ABI tests preserve Solidity lazy calldata-address validation and receive behavior.
- GasCompZapper: LST collateral lifecycle, ETH gas compensation, manager checks,
  flash-loan closing, safe token handling and rollback. Six differential tests
  plus a connected LST-branch lifecycle pass.
- LeverageWETHZapper and LeverageLSTZapper: individual/batch leveraged opening,
  lever-up/down, inherited base operations, ratio conversion and exact ABI/error
  behavior. Eight parity tests and two actual connected protocol lifecycles pass.
  Fixed constructor-created companions preserve the original constructor and
  EVM size limits; see ZAPPERS_DEPLOYMENT.md.
- CurveExchange, UniV3Exchange, UniPriceConverter and HybridCurveUniV3Exchange:
  exact-input/output swaps, refunds, packed paths, fee/index widths, price rounding
  and checked arithmetic. Thirteen differential tests and four actual connected
  Curve/UniV3 leverage lifecycles pass; quote helpers and the flash-loan provider are covered below.
- AddRemoveManagers: authorization, configuration, receiver selection and clearing.
- LiquityBase: registry configuration, branch totals, ratios and interest helpers.

The connected metadata test deploys actual Fe TroveNFT, MetadataNFT and
FixedAssetReader; only the manager/registry/collateral-token dependencies are mocks.
The renderer creates a stateless MetadataGeometry companion using CREATE in its
constructor, preserving the original public constructor arguments. Asset and token
calls remain in the main renderer. The companion only assembles supplied bytes.
Runtime sizes are 23,721 bytes (MetadataNFT) and 18,538 bytes (companion); main
initcode is 42,596 bytes before its 32-byte constructor argument. All size limits
are enforced. Companion deployment and output are tested directly.

PoolSystem connects real Fe pools, registry and BOLDToken. StabilityPoolSystem
also connects the actual Fe StabilityPool, exercising real interest minting,
offsets and claims. Both tests drive BO/TM-side operations and do not establish
a complete borrowing/liquidation deployment.
TroveChange, LatestTroveData and LatestBatchData ABI support are integrated.
TroveManagerSystem connects actual Fe manager modules, pools, registry, BOLDToken,
SortedTroves, TroveNFT and GasPool. It drives BO-side hooks; collateral and price
feed are controlled test contracts. BorrowerOperationsSystem uses the real Fe
BorrowerOperations and its modules with those actual Fe components. It compares
user borrowing, rate/batch changes, closing, liquidation, redemption and shutdown
against an all-Solidity branch, with collateral and price inputs controlled. A further connected test deploys
the actual Fe WETHPriceFeed and verifies oracle failure shuts down both
BorrowerOperations and TroveManager, freezes the fallback price, rejects new
borrowing, and still permits closing.

`port_status.json` retains all 102 core/helper sources; `governance_status.json`
retains all 27 governance sources. Unused generic SVG/JSON/Utils/baseSVG entry
points remain explicitly partial even though all renderer behavior is tested.

## Compiler and reference

- Solidity reference: `c8a5a4ee2e9dc024905856b6698a77d849c68c7e`.
- Latest upstream/master, rechecked with ls-remote:
  `3dd15a62124fb75370c7931c4ee040d8566a3649`.
- Compiler integration: `27976c7df7d0fca487f2c80f26241c9021dfa04c`, branch
  `liquity-v2-integration`, including existing PRs #1592, #1587, #1585 and #1567.
- Prior integration: 243 type-check fixtures, 218 HIR unit tests and 25 execution regressions passed.
- With #1567: all 98 MIR tests and four payable-return release execution tests pass;
  the complete protocol suite above runs on the rebuilt release compiler.
- New compiler fix: reject integer expression literals wider than 256 bits,
  on separate branch `fix/reject-oversized-integer-literals` at `b11dee2`.
  The independently tested branch is now integrated into the protocol compiler. See COMPILER_FIXES.md for patch and newsfragment.
- Fresh bootstrap verifies the exact integration tree and all pinned ancestors;
  locally generated merge commit timestamps need not be identical.
- Reference/dependency sources and five font/logo assets are hash-checked.

The renderer uses pairwise concatenation. Earlier generic tuple/array variants
were slow to compile and monolithic bytecode exceeded EIP-170. Investigation
is preserved in `tests/repros/metadata_tuple_concat.*`; PR #1585 alone is not
claimed to resolve the compile-time issue. Generated geometry/literal sources
are reproducible with `scripts/generate_bauhaus.py` and
`scripts/generate_metadata_literals.py`.

## Next work

1. Implement Governance and integrate/validate the prepared initiatives.
2. Remaining helper/library interfaces.
3. Governance and full multi-branch deployment/lifecycle/invariant validation.

Preserve Solidity operation ordering, revert data and rounding. SortedTroves
reinsertion occurs before updating the manager's reported interest rate.
Native storage borrows cannot span external calls; raw handles/copies preserve
storage access ordering without weakening compiler checks. Any newly authored
compiler fix needs its own branch, regression tests and newsfragment.

BorrowerOperations preserves Solidity slots 0–12, including the packed shutdown
flag at byte 20 of slot 9. Runtime sizes: main 13,892 bytes, opening 12,052,
adjustments 22,580, batches 23,828. Its constructor takes the registry and three
fixed module addresses. The registry WETH getter uses CALL as declared by the
Solidity interface; a stateful constructor mock checks this behavior.

HybridCurveUniV3ExchangeHelpers, its V2 variant and BalancerFlashLoan are now
included in the completed root checkpoint. Five quote-helper parity tests cover
both quote directions, signed indices, packed paths, malformed returndata and
memory-allocation panic boundaries. Seven provider parity tests cover all four
flash callbacks, fees, ABI validation and rollback. Eight connected lifecycles
use the actual Fe provider, Curve/UniV3 exchanges, WETH/LST zappers and core;
only the external vault and trading venues are mocked. ABI and size audits pass.

### Governance progress

The root checkpoint now includes UserProxy, UserProxyFactory, Math/VotingPower,
DoubleLinkedList, BribeInitiative, CurveV2GaugeRewards, UniV4MerklRewards, the
OpenZeppelin 5 token helper, and the Governance snapshot/status calculation
module. The latter is tested against actual Solidity Governance through a
harness; it is not the complete Governance contract. All 291 EVM tests and two
Fe tests pass, as do the ABI and size audits. Main Governance and full-system
completion remain outstanding.

The remaining Governance work is prepared in `/tmp/liquity-governance-project`,
with tests in `/tmp/liquity-governance-inspect`, artifacts in
`/tmp/liquity-governance-build`, and an isolated ABI audit in
`/tmp/liquity-governance-audit`. Three staking tests, two hook tests, three action
tests and three voting/reset tests pass against Solidity. Their logs are
`/tmp/liquity-governance-{staking,hooks,actions,voting}-parity.log`. They cover
real reentrancy, atomic rollback, offset rounding, event bytes/order, cached
storage during callbacks, cutoff rules and disabled-initiative reset. The hook
helper can also be built quickly through `/tmp/liquity-hooks-project`.

A composed `governance.fe` now connects these modules, the original constructor
arguments, getters, ownership and initial registration. Its current build is
`/tmp/liquity-governance-build.log`; it has not yet been size-checked or tested as
a whole. Multicall is still missing. The memory-address wrappers distinguish
ordinary function and constructor decoder allocation bounds; verify their
extreme lengths and eager address validation against Solidity before integration.

Authoritative Solidity storage layout: `/tmp/liquity-governance-storage.json`.
Slots: reentrancy 0, owner 1, accrued BOLD 2, global snapshot 3–4, initiative
snapshots mapping 5, global state 6–7, users mapping 8, initiatives mapping 9,
allocations nested mapping 10, registration mapping 11. The source inventory
keeps Governance partial until the complete contract and connected workflows
are validated. No new compiler fix was needed for this governance work.
