# Current work state

The complete Liquity V2 port goal remains active. The verified contracts below
are a partial system; remaining library/interface coverage and
complete multi-branch workflows are still outstanding.

## Validated checkpoint

`./scripts/test.sh` passes **351 EVM tests and 2 Fe tests**, with 1,024 runs per
fuzz test plus cached regression inputs. Sources, scripts, tests, artifacts,
compiler and reference hashes are recorded in `tests/results/metadata-multibranch.json`;
the complete log is `tests/results/metadata-multibranch.log`.

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

1. Finish remaining metadata utility and interface coverage.
2. Remaining helper/library interfaces.
3. Reproducible deployment and broader multi-branch stateful invariant validation.

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

Full Governance is integrated into root sources and tests. It uses fixed
Staking/Voting/Actions delegate modules, with the original seven constructor
arguments followed by the three module addresses. See GOVERNANCE_DEPLOYMENT.md.
Its isolated connected validation passes 25 tests plus ABI and deployment-size
audits; input/compiler/artifact hashes and logs are preserved in
`tests/results/governance-prepared.*`. This is not yet a root full-suite proof.

Coverage includes staking/rewards, permits, reentrancy, allocation/reset and
rounding, cutoff and status rules, snapshots, registration/claim/unregistration,
initial ownership and events, extreme constructor-array lengths, and nested
multicall rollback. Connected lifecycles exercise all three Fe initiatives
with actual Fe Governance and UserProxy. The constructor decoder accounts for
Solidity's immutable memory reservation and copied argument length, including
unaligned trailing bytes. No new compiler fix was required.

Runtime sizes: Governance 15,847 bytes, StakingModule 7,324, VotingModule 21,116,
ActionsModule 13,409. Parent initcode is 26,432 bytes before arguments; module
initcode is runtime size plus 20 bytes. All satisfy EVM limits. Modules are
immutable and have no upgrade path. ABI exports record the actual constructor.

Next: full root `./scripts/test.sh`, record proof immediately before any further
source/test/script edits, then update the inventory and commit. The previous
complete root proof remains 291 EVM tests + two Fe tests at `bc3690b`.
Remaining overall scope includes complete multi-branch workflows, deployment,
invariants and the explicitly unfinished utility/interface coverage.

Root full-suite session `13809` is running with output in
`tests/results/governance.log`. Reference-source, dependency and asset checks
have passed. Freeze root sources, tests and scripts until it finishes, then
run `python3 scripts/record_validation.py tests/results/governance.log`
immediately if successful. Do not restart this job solely because it is slow.

### Prepared multi-branch validation

Root sources/tests/scripts remain frozen during session `13809`. Independent
work lives in `/tmp/liquity-multibranch-inspect`, using a copied, stable set of
core build artifacts. `MultiBranchFixture.sol` and `MultiBranchSystem.t.sol`
deploy three actual core branches sharing BOLD and a CollateralRegistry, with
branch-specific CREATE2 salts. No root source or test has been changed for this.

Three initial tests passed, including 1,024 fuzz runs of cross-branch redemption,
local liquidation/offset/redistribution and shutdown, with exact Solidity state
comparisons and shared supply == sum(recorded branch debt) invariants. Proof:
`/tmp/liquity-multibranch-fuzz.{log,json}`. Additional tests pass with actual
WETH/RETH/WSTETH Fe price feeds and with an oracle-triggered shutdown isolated
to one branch while redemptions continue through the others. Their logs are
`/tmp/liquity-multibranch-real-feeds.log` and
`/tmp/liquity-multibranch-oracle-failure.log`. Tokens/oracle data providers remain
controlled test doubles. A final five-test run is now writing
`/tmp/liquity-multibranch-prepared.log`; record source/artifact hashes before
editing or integrating those prepared tests. The fixture avoids inheriting
existing tests. Integrate only after the current root validation is recorded.

The final isolated five-test multi-branch run passed, including 1,024 fuzz runs.
Proof captured before further edits in `/tmp/liquity-multibranch-prepared.json`
with log `/tmp/liquity-multibranch-prepared.log`. Root session `13809` remains
running; do not integrate these tests until its proof has been recorded.

The prepared suite now also deploys actual Governance/BribeInitiative and routes
all three ActivePools' interest-router payments into Governance. A voter stakes,
allocates, deposits a bribe using actual BOLD approval/transfer, claims both real
protocol interest and the bribe, and exits. The V1 staking mock is ETH-funded
for its reward behavior. All six tests pass together (1,024 fuzz runs), with
proof in `/tmp/liquity-multibranch-governance-prepared.{log,json}`. Governance
artifacts in the isolated build directory were copied from the already verified
isolated Governance build. The root remains frozen for session `13809`.
Upstream master was rechecked on September 25 and remains `3dd15a62`.

### Prepared metadata utilities and compiler diagnostic fix

JSON and all 33 SVG function overloads are implemented separately in
`/tmp/liquity-metadata-utils-project` and tested in
`/tmp/liquity-metadata-utils-inspect`. Five differential tests pass, with 1,024
runs per fuzz test, in `/tmp/liquity-metadata-json-svg-parity.{log,json}`. SVG
uses two harness contracts to stay within deployment limits. These utility
sources are not yet in root; remaining Utils/baseSVG coverage is still open.

An unsupported inline string constant (`String<33>`) revealed a compiler panic
instead of a type diagnostic. Minimal input: `/tmp/liquity-string-constant-repro`.
No matching open PR was found among current PRs. Isolated compiler worktree
`/tmp/fe-string-constants`, branch `fix/reject-oversized-string-constants`, based
on current upstream master, now diagnoses invalid constant declaration types
in check_const_body. Five negative input cases and the valid 31-byte boundary
pass in two new regression tests; a newsfragment is present. Full HIR tests
are running, CLI validation and committing/reporting remain pending. The root
compiler checkout and release binary remain unchanged during the root build.
The previously pushed integer-literal fix now has upstream PR #1595 (observed
via GitHub); this agent did not create that PR.

Compiler fix detail: the missing diagnostic is on the const declaration's type,
not a need to permit inline strings above 31 bytes. The change adds existing
TyId diagnostics at the const type span in check_const_body. Regression tests
use initialize_analysis_pass (the focused test pass alone does not exercise all
user-facing behavior). Targeted tests and cargo fmt --check pass. Full fe-hir
--tests session `12102` remains live (one pre-existing exhaustive sparse-array
capability test is slow). Debug CLI build session `5497` is queued/running against
the separate worktree, sharing only the debug target cache; the root release
binary is unchanged. CLI repro, final test results, commit and fix report still
need completion. New regression test and newsfragment are untracked in that
worktree until commit. No new fix branch has been pushed.

Metadata JSON/SVG sources and tests are now frozen at their five-test passing
proof in `/tmp/liquity-metadata-json-svg-parity.json`. Test harnesses are
MetadataJsonHarness, MetadataSvgHarnessA and MetadataSvgHarnessB; ignore the
obsolete single MetadataSvgHarness artifact left in that temporary build folder.
Root full-suite `13809` has passed both Fe tests and is building all O1 artifacts
(PID 4122545 last observed live). Record its validation before any root
source/test/script changes.

## Governance checkpoint completed

Root session 13809 completed successfully: 331 EVM tests, two Fe tests, all O1
builds, reference checks and ABI/size audit passed. Proof was recorded immediately
in tests/results/governance.json before source/test/script changes. The source
freeze is lifted. Full Governance is now integrated, including the constructor,
staking, voting/reset, actions, ownership and multicall, with connected initiative
and reward lifecycles. External tokens and V1 staking remain controlled fixtures.

Compiler diagnostic fix 35502252d was pushed, at the user's request, to upstream
branch fix/reject-oversized-string-constants. The CLI reproducer now reports
error 3-0033 instead of panicking; both regression tests and formatting pass.
The full HIR suite is still running in session 12102. The protocol compiler
release binary remains unchanged. Earlier pending/push notes above are historical.

## Multi-branch tests integrated

All six MultiBranchSystem tests pass in root against the validated root artifacts,
including 1,024 fuzz runs. The test/source/artifact hashes are captured in
tests/results/multibranch.json. These add three-branch redemptions, liquidation,
shutdown isolation, actual price feeds, protocol interest routed to Governance
and bribe claims. The six tests supplement the 331-test full checkpoint; a new
complete test.sh run has not yet been made after their addition. A reproducible
non-test deployment command and broader stateful invariants remain outstanding.

## Metadata utilities, randomized branch actions and compiler refresh

Prepared JSON/SVG/Utils/baseSVG suites pass all 13 tests, with 1,024 runs per
fuzz test. Sources and normalized tests are now integrated. Exact CSS spacing,
all SVG overloads, numeric/revert boundaries, arbitrary UTF-8 bytes, base SVG
elements and asset-reader failures are covered. Proof: metadata-utilities-prepared.

A new three-branch test passes 1,024 random 24-action sequences against Solidity.
Actions include collateral/debt changes, rate changes, pending debt application,
SP deposits/withdrawals and redemptions; time advances between actions. Each step
checks conservation, shared supply, return/revert bytes and trove/depositor state.
Proof: multibranch-stateful-prepared. It is now integrated in root.

Compiler release now uses upstream/master f1f89a9dd plus pinned fixes at
061763900, tree 17b20419. Fresh merge replay matches. Dedicated ABI (19),
CLZ/CTZ (4) and payable return (4) execution tests pass. String-constant full
HIR tests encountered a layout assertion also reproduced on the unchanged base;
see compiler-string-constants evidence. Root full validation is starting against
all these changes. Freeze root sources/tests/scripts/compiler until it finishes
and record the resulting proof immediately.

## Prepared runnable local deployment

/tmp/liquity-local-deployment now deploys the actual Fe bytecodes through ordinary
transactions to Anvil (Cancun, normal code/initcode limits). It includes three
branches, shared BOLD/registry, Governance and BribeInitiative, original NFT assets
and renderer, and query/redemption helpers. DevToken/DevOracle/DevRate/DevStaking
are explicitly external local fixtures. Deployment and smoke succeeded: six
troves, SP deposits, full NFT rendering, real interest to Governance, bribe claims,
LQTY exit, redemptions, liquidation and shutdown, with conservation checks.
Proof: /tmp/liquity-local-deployment/validation.json and smoke-result.json.
Anvil session 42806 is ours, port 18545; leave unrelated services alone. The smoke
intentionally shuts down one branch. This script is not yet root-integrated and
uses copied artifacts from the earlier validated compiler checkpoint. It still
needs a portable runner, remaining zappers/exchanges deployment/configuration,
and replay with the refreshed root artifacts after session 57870 finishes.
Root remains frozen while the full test.sh run is in flight.

## Prepared complete interface bindings

/tmp/liquity-interface-project contains 65 actual interfaces (517 methods,
61 events, two errors) extracted from all pinned interface source files. An
earlier count of 66 included concrete MetadataNFT and was corrected. Full
integer widths use std ABI wrappers. Twenty-five large static records use
explicit field codecs; their roundtrip harness passes 1,024 differential fuzz
runs plus truncated/invalid scalar inputs. All 62 callable-interface selector
tests pass against Solidity methodIdentifiers. Proof is
/tmp/liquity-interface-validation.json; index /tmp/liquity-interface-index.json.
No interface sources are integrated into root yet. The generator scripts in
/tmp still need portable packaging; InterfaceRecordParity.verified.t.sol
preserves the strengthened final tests (draft generator has weaker assertions).
Decoder implementations advance the cursor before decoding through immutable
ByteInput because nested mutable generic decode_payload calls triggered a
compiler borrow conflict; no compiler change was needed.

Portable local deployment was rechecked with run.py --smoke, using a separately
started/stopped Anvil on port 18546. Evidence is now
/tmp/liquity-local-deployment-portable-check/validation.json, which pins the
portable runner sources and all artifacts. Old deployment validation hashes
predate runtime.py/run.py and should not be used for those updated scripts.
Root session 57870 has passed its two Fe tests and is building O1 artifacts.
Continue waiting on the same handle and record its proof before root changes.

## Full local deployment extension prepared

/tmp/liquity-local-deployment-v2 now deploys all four zapper types, Curve/Uni/Hybrid
exchanges, both quote-helper generations, the Fe Balancer adapter, Constants,
and Curve/Merkl initiatives in addition to the existing three-branch system.
The complete smoke run passes in /tmp/liquity-local-deployment-batch2-check: all
zappers open/close; all leveraged adapter routes open/up/down/flash-close; batch
join/fee/rate/pending-debt/exit; NFTs; SP; all governance reward routes; liquidation,
redemptions and shutdown; conservation throughout. Its validation.json pins the
portable scripts, fixture sources, artifacts and transaction reports. This uses
the earlier copied artifact checkpoint until root build 57870 finishes.

The external DevBalancerVault and DevDistributionCreator fixtures are installed
at the canonical addresses required by the unchanged reference interfaces. All
Fe protocol contracts use ordinary deployments, with normal EVM size limits.
Demo governance uses one-day epochs: the added batch interest time jump made
the former 100-second demo epochs expire idle initiatives before voting. The
1-day config passes the complete combined workflow. External token/oracle/market
fixtures remain explicitly marked in the deployment manifest. Initial standalone
Anvil session 42806 (PID4193928, port18545) has been terminated; portable runners
stop only their own Anvil children automatically.

Portable interface generators are prepared in /tmp/liquity-interface-package/scripts.
They rebuild ABIs from pinned hashes and reproduce all 65 source modules exactly.
Generated selector/record harness Fe files match the verified sources; regenerated
Solidity record tests pass (including canonical scalar failures and 1,024 fuzz runs).
Hierarchical interfaces module packaging passes Fe check. Nominal TroveId and the
remaining SVG namespace constants (as owned-string functions) are prepared and
Fe-checked in /tmp/liquity-port-extras-project. None is root-integrated yet.

## Refreshed complete protocol checkpoint

Session 57870 completed successfully: 351 EVM tests, two Fe tests, reference
checks, all O1 builds and ABI/size audit. Proof was recorded immediately in
tests/results/metadata-multibranch.json before source changes. The full local
deployment/transaction smoke also passes against these exact refreshed artifacts:
/tmp/liquity-local-deployment-refreshed-check/validation.json. It recorded 128
deployment transactions, 94 zapper/batch transactions and 61 core/governance
transactions; the largest used 8,943,184 gas. Root source freeze is now lifted
for integration of the prepared interfaces, ID/namespace helpers and local runner.
Upstream master was rechecked and remains f1f89a9dd.
