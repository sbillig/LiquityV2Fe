# Compiler fixes

Local integration checkout: `toolchain/fe`, branch `liquity-v2-integration`.
Current upstream/master: `3dd15a62124fb75370c7931c4ee040d8566a3649`.

Three existing upstream fixes and one new independently tested fix have been
integrated. The new fix remains available on its own published branch.

Build setup: `npm ci --prefix crates/tree-sitter-fe` is needed before Cargo can
generate the parser. This is an environment dependency, not a compiler defect.

Each discovered compiler defect must be reproduced independently, fixed on its
own branch, covered by regression tests and accompanied by a newsfragment.
Record branch, commit, reproduction, tests and integration commit here.

## Integrated: long error and event names (upstream PR #1592)

- PR: https://github.com/argotorg/fe/pull/1592
- Local branch: `fix/1592-long-signature-hashing`
- PR head: `04baed1a6b2e24e3a70fda5cfb0a9d781ae743e4`
- Integration merge: `4db4b8110b49e41c3df2698d12969be011f56cde`
- Trigger: `BorrowerOperationsAddressChanged` and
  `CollateralRegistryAddressChanged` fail generated TOPIC0 evaluation on master.
- Regression: `crates/fe/tests/fixtures/fe_test/long_error_event_names.fe`:
  all 10 execution tests pass with the rebuilt compiler.
- Newsfragment: `newsfragments/+long-error-event-names.bugfix.md`.
- Existing upstream PR; no new submission is needed for this fix.

## Investigated but not integrated: PR #1575

Branch `liquity-v2-borrow-investigation` tested PR #1575 against an ActivePool
storage-borrow diagnostic. The rejection is intentional: Fe forbids native storage
borrows across external calls. The integration checkout was returned to
`liquity-v2-integration` and rebuilt. No new compiler defect/fix resulted.
`tests/repros/storage_call.fe` records the intentionally rejected pattern.

The ActivePool port ends storage borrows before external calls and preserves the
Solidity order of state reads/writes. BOLDToken binds its StorageMaps independently
of scalar storage fields. Its EIP712 metadata uses an explicit flat Solidity
return instead of Fe's single dynamic tuple return; this is ABI adaptation, not a
compiler modification. All resulting protocol runtime tests pass.

## Integrated: unpadded dynamic ABI payloads (upstream PR #1587)

- PR: https://github.com/argotorg/fe/pull/1587
- Local branch: `fix/1587-unpadded-dynamic-abi`
- PR head: `c22b24357` (full revision pinned in `reference_manifest.json`).
- Integration merge: `5903581eecd9ce0edf78884feeef087729973e5d`.
- Trigger: ERC721 `safeTransferFrom(address,address,uint256,bytes)` with one
  actual data byte and omitted trailing padding succeeds in Solidity, but the
  previous Fe decoder reverted. `testAbiValidationAndUnpaddedBytes` reproduces it.
- Regression: `crates/fe/tests/fixtures/fe_test/abi_unpadded_dynamic_payload.fe`;
  checks bounded copies, zeroed allocation padding, nested dynamic arrays,
  decode/re-encode paths and rejection of missing actual bytes.
- Newsfragment: `newsfragments/1587.bugfix.md`.
- Existing upstream PR; no new submission is needed for this fix.
- Validation is recorded in `tests/results/compiler-1587.log` and the full
  protocol run in `tests/results/sorted-nft.log`.

SortedTroves and TroveNFT read-only external calls use Fe's mutable `Call`
capability for STATICCALL. Its conservative ABI metadata says `nonpayable`;
`export_abi.py` explicitly normalizes the three runtime-tested view functions.
Raw-storage getters declare their capability per handler to retain `view` ABI
metadata. No compiler modifications are needed for these metadata adaptations.

## Integrated: borrow-analysis performance (upstream PR #1585)

- PR: https://github.com/argotorg/fe/pull/1585
- Local branch: `fix/1585-borrow-analysis-performance`.
- PR head: `c4856b4fb6e5383d3f31c95312f966dec9491233`.
- Integration revision is pinned in `reference_manifest.json`.
- Trigger under investigation: metadata ingot compilation spent over twenty
  minutes in analysis; even ABI-only export remained busy. Both old-compiler
  jobs were explicitly stopped to evaluate this existing upstream fix.
- The PR includes regression tests for guard size, quantification, source cache
  invalidation, summary mappings, and control-flow ordering.
- No newsfragment is supplied by this existing upstream PR. This integration did not author a new compiler
  fix. All 218 `fe-hir` library unit tests pass
  (`cargo test --release -p fe-hir --lib --locked`), recorded in
  `tests/results/compiler-1585.log`. The 10 PR #1592 and 14 PR #1587
  execution regressions also pass with this integration compiler.
  The full 96-test EVM / 2-test Fe suite passes with this compiler.
  Tuple and uniform-array concatenation remained slow; the final renderer uses
  pairwise concatenation. PR #1585 alone is not claimed to resolve that slowdown.

Reproducibility: `reference_manifest.json` pins the complete integration tree as
well as upstream and PR input commits. Fresh bootstrap merges can have different
commit IDs because local merge timestamps differ; the bootstrap and validation
recorder require the exact pinned tree and all input commits as ancestors.

## New: reject integer expression literals wider than 256 bits

- Branch: `fix/reject-oversized-integer-literals` in `toolchain/fe`.
- Commit: `b11dee2befde6aabfc8d7fef4fa7eac5ce4a44b4`.
- Base: upstream/master `f00132a97429f966804d70c40206ef40ebca6960`;
  this is a standalone patch without the three integration PRs as dependencies.
- Worktree: `/tmp/liquity-fe-wide-literals`.
- Patch: [reject-oversized-integer-literals.patch](compiler-patches/reject-oversized-integer-literals.patch).
- Trigger: a 33-byte integer used to assemble a string was accepted and silently
  truncated to its low 256 bits. The independent reproduction
  `tests/repros/oversized_integer_literal.fe` demonstrates that `2^256` currently
  executes as zero on the pinned protocol compiler.
- Fix: diagnose integer expression literals wider than 256 bits before lowering.
  This patch concerns the maximum primitive integer width; it does not claim to
  change all narrower integer-conversion rules.
- Regression: `crates/uitest/fixtures/ty_check/oversized_integer_literals.fe`
  and its diagnostic snapshot cover oversized hexadecimal/decimal returns,
  call arguments and inferred locals; valid `u256` maximum and `i256` minimum
  remain accepted.
- Newsfragment: `newsfragments/+oversized-integer-literals.bugfix.md`.
- Verification: all **243** `fe-uitest` type-check fixtures and **202** `fe-hir`
  library tests pass on this branch; `cargo fmt --all --check` passes.
  Logs and hashes: `tests/results/compiler-wide-literals-*`.
- Integration status: merged locally at `14779075e25fad96e0e1e1755fa6b9ff8eb9f087`
  after updating to upstream/master `3dd15a621`. Earlier checkpoints retain their
  original compiler hashes. The port's erroneous constants were corrected and all
  source literals were checked for excessive width.
- Published branch: [fix/reject-oversized-integer-literals](https://github.com/argotorg/fe/tree/fix/reject-oversized-integer-literals),
  pushed to upstream at the user's request on 2026-09-24; merged upstream as PR #1595.
- Duplicate check: no matching open PR among the 39 open PRs checked. Historical
  [PR #247](https://github.com/argotorg/fe/pull/247) addressed the same bound in
  the old analyzer and was merged on 2021-02-15; it should be referenced in a
  future PR description.

## Updated upstream integration (2026-09-24)

The local build now includes upstream/master `3dd15a621`, including #1592
(now upstream), #1593 (bounded staticcall compatibility), and #1594 (integer
width for view-typed constant evaluation), plus the previously integrated fixes
and the new oversized-literal fix. Integration: `14779075e25fad96e0e1e1755fa6b9ff8eb9f087`.

All 243 type-check fixtures, 218 HIR tests, and 25 dedicated execution regressions
pass. Evidence is in `tests/results/compiler-updated.*` and the associated logs.
Replaying every pinned merge from the new upstream base in a separate clean
worktree produced the same integration tree `0d1d3cedde2c9305c0d9219ee9de866e88d8e545`.

## Integrated payable return handlers (upstream PR #1567)

- PR: https://github.com/argotorg/fe/pull/1567, still open when checked.
- PR branch: `fix/1567-payable-returns`, head
  `8557f3f5e56c17801743469f6d46377ecd58c572`.
- Trigger: `tests/repros/payable_return.fe` fails on the previous release compiler
  with `InvalidReturnClass`; WETHZapper's payable opening function needs this.
- Initially prepared on integration branch: `liquity-zapper-integration`, commit
  `27976c7df7d0fca487f2c80f26241c9021dfa04c`, worktree
  `/tmp/liquity-fe-zapper-compiler`. Only an import-list merge conflict needed
  resolution: retain both `RuntimeLinkage` and `RuntimeReturnPlan`.
- The four execution tests pass at O0, O1, O2 and Os; the targeted verifier
  regression also passes. Logs: `tests/results/compiler-1567-*`.
- Newsfragment supplied by upstream: `newsfragments/1567.bugfix.md`.
- This is an existing upstream PR, not a newly authored compiler fix. It is now
  included in the pinned release compiler on `liquity-v2-integration` at the
  integration commit above. The rebuilt release binary passes the complete
  protocol suite: 210 EVM tests and 2 Fe tests (`tests/results/weth-zapper.*`).
- All 98 MIR library tests and the four payable-return release execution tests
  pass. The earlier O0/O1/O2/Os execution checks remain recorded separately.
- `scripts/merge_compiler_fix.py` replays only the exact reviewed import conflict,
  rejecting unexpected conflicts. A fresh replay produced the pinned source tree
  `e8e5d938074145678e2ec2f01c6e14e50cb99638`.

## Invalid constant type diagnostics

- Branch: [fix/reject-oversized-string-constants](https://github.com/argotorg/fe/tree/fix/reject-oversized-string-constants), pushed to upstream at the user's request.
- Commit: `35502252d6f7873e9bd1928388633319145c871b`, based on upstream/master `3dd15a621`.
- Invalid declared constant types previously bypassed diagnostics and could panic
  during CTFE. `check_const_body` now emits the existing type diagnostic.
- Regression file: `crates/hir/tests/invalid_string_constants.rs`: five invalid
  inputs plus the valid 31-byte boundary, including an associated const and UTF-8.
- Newsfragment: `newsfragments/+invalid-constant-types.bugfix.md`.
- Both regression tests and formatting pass. A built debug CLI reports error
  3-0033 for the original String<33> reproducer. The full HIR suite stops at
  `non_regular_recursive_effect_handle_views_are_rejected` (layout root coverage
  assertion); the exact same test and assertion fail on the unchanged base
  commit. This is a pre-existing failure, not a passing full-suite claim.
  Logs and hashes: `tests/results/compiler-string-constants.*` and associated logs.
- Not merged into the protocol release compiler; valid port code does not need it.

## Latest upstream refresh

Upstream master is now `f1f89a9ddf4a730c7dd11a66a37af0add7a23d0d`, including
#1587, #1595 and #1597 (CLZ/CTZ and Osaka test harness). Local integration
`0617639002e12e599fd7bfb68bd2722215c8a935` retains the other pinned fixes.
A fresh replay from the new base produces the identical tree
`17b20419e39a12c49b0e09d5b67053812c16504e`. Release build and 27 targeted execution tests pass (19 ABI, four CLZ/CTZ,
four payable returns). Proof: `tests/results/compiler-refresh.json`. The new
full protocol validation is still running. Solidity differential tests
remain on Cancun. The string constant diagnostic branch is still separate.
