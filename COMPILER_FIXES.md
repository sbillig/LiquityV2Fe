# Compiler fixes

Local integration checkout: `toolchain/fe`, branch `liquity-v2-integration`.
Base upstream/master: `f00132a97429f966804d70c40206ef40ebca6960`.

Three existing upstream fixes have been integrated. One new independently tested
fix is ready on a separate branch; it is not merged into the protocol compiler.

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
- Integration status: deliberately separate from the protocol compiler while
  its recorded validation runs use the pinned integration tree. The port's
  erroneous constants were corrected and all source literals were checked for
  excessive width. No PR was published or external message sent.
