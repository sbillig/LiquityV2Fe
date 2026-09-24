# Compiler fixes

Local integration checkout: `toolchain/fe`, branch `liquity-v2-integration`.
Base upstream/master: `f00132a97429f966804d70c40206ef40ebca6960`.

One existing upstream fix has been integrated (details below). No new compiler fixes have been authored.

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
