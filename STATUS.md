# Current work state

The complete pinned Liquity V2 inventory is implemented, including Governance,
metadata utilities, typed interfaces and a runnable three-branch local deployment.
The final integrated validation and deployment artifact comparison both pass. See [COMPLETION_AUDIT.md](COMPLETION_AUDIT.md) for the
requirement-by-requirement evidence.

## Validation

- **353 EVM tests and 64 Fe tests pass**, recorded in
  `tests/results/complete-port.json` and its full log.
- `./scripts/test.sh` completed successfully: reference/dependency/asset checks,
  Fe tests, optimized build, 63 EVM suites, ABI audit of 41 protocol contracts
  and size checks of all 53 protocol/module/companion contracts.
- Fuzz tests use 1,024 runs plus cached regression inputs. Coverage includes
  success/revert bytes, state, events, operation ordering, arithmetic boundaries,
  randomized sequences and connected protocol lifecycles against pinned Solidity.
- Provenance was recorded immediately after success. Recursive Fe sources, tests,
  scripts, configuration, deployment sources, compiler and artifacts are hashed.
- This final run includes all 62 interface-selector tests and both static-record
  parity checks. The earlier 351-EVM/two-Fe checkpoint remains separately recorded
  in `tests/results/metadata-multibranch.json`.

## Implemented scope

`port_status.json` maps all **102** core/helper reference files;
`governance_status.json` maps all **27** governance files. Direct comparison with
both reference trees finds no missing or extra entries. All mapped source and
verification files exist. The mappings distinguish executable implementations,
external interface declarations and nominal types.

The implementation includes borrowing and batch management, interest accounting,
liquidation/redistribution, regular and urgent redemptions, StabilityPools,
three collateral branches, token/permit/NFT behavior, all price feeds and shutdown,
helpers, all four zappers, exchange adapters and Balancer integration. Governance,
UserProxy/factory and the Bribe, Curve-gauge and Merkl initiative lifecycles are
implemented and connected to actual branch interest income.

Metadata includes the original assets, full NFT rendering and the generic
JSON/SVG/Utils/baseSVG entry points. The typed bindings cover 65 interfaces,
517 methods, 61 events and two errors. All 517 selectors pass integrated Fe tests;
25 larger static records have Solidity differential codec tests. Nominal
BatchId/TroveId wrappers and SVG namespace constants have explicit compile and
inspection evidence. See [INTERFACES.md](INTERFACES.md).

Fixed modules keep BorrowerOperations, TroveManager and Governance within EVM
limits; their constructor adaptations are documented in the corresponding
`*_DEPLOYMENT.md` files. Runtime selectors are preserved. Generated ABI exports
and the size audit are produced by the full suite.

## Runnable local system

```sh
python3 tools/local_demo/run.py
# Or exercise the full transaction smoke and stop its Anvil:
python3 tools/local_demo/run.py --smoke
```

The packaged smoke has passed with **128 deployment transactions**, **94 zapper/
batch transactions** and **61 core/governance transactions**, using the current
compiler. Evidence: `tests/results/local-deployment.json` and its associated
reports/log. The seven deployment input hashes, three report hashes and compiler
binary hash were rechecked against the current files.

The local system uses actual Fe protocol contracts with ordinary deployment and
normal runtime/initcode limits. Tokens, oracle sources, V1 staking, DEX markets,
Balancer vault, gauge and Merkl creator are declared local external fixtures.
See [LOCAL_DEPLOYMENT.md](LOCAL_DEPLOYMENT.md) for setup and exact scope.

All **150 recorded bytecode files match the final integrated build exactly**.
The comparison and full-validation hash are recorded in the deployment proof;
no smoke replay was needed.

## Compiler and reproducibility

- Pinned Solidity core: `c8a5a4ee2e9dc024905856b6698a77d849c68c7e`.
- Fe upstream/master: `f1f89a9ddf4a730c7dd11a66a37af0add7a23d0d`.
- Local release integration: `0617639002e12e599fd7bfb68bd2722215c8a935`.
- Reproduced integration tree: `17b20419e39a12c49b0e09d5b67053812c16504e`.
- The release build and 27 focused ABI/CLZ/payable execution tests pass;
  `tests/results/compiler-refresh.json` records their scope.
- Authored integer-width fix: separate branch, regression tests and newsfragment;
  merged upstream as #1595.
- Authored invalid string-constant diagnostic fix: separate branch, regression
  tests and newsfragment; pushed upstream at the user's request. Focused tests,
  formatting and CLI reproduction pass. A broad HIR test failure was reproduced
  on the unchanged base and is explicitly reported, not claimed as passing.
  This diagnostic-only fix is separate from the protocol release compiler.

[COMPILER_FIXES.md](COMPILER_FIXES.md) records revisions, tests and limitations.
Bootstrap reproduces the exact compiler source tree and verifies pinned ancestors;
reference/dependency sources and all five assets are hash-checked. Upstream master
was rechecked after the final suite and still matches the pinned revision. Earlier checkpoint chronology is
preserved in Git and the individually named evidence files.
