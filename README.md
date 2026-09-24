# Liquity V2 in Fe

Work in progress: this repository is not yet a complete or deployable Liquity V2 port.

The target is the complete Liquity V2 contract system, preserving the behavior of
[liquity/bold](https://github.com/liquity/bold), including interest and batch
accounting, liquidation and redistribution, redemptions, stability pools,
collateral branches, authorization, token/NFT behavior, oracle shutdowns, helpers
and zappers. The source inventory in `port_status.json` deliberately retains
unimplemented contracts. Passing foundation tests does not establish protocol
completion. Governance integration must also be covered before completion.

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
deployment command. These checks are not yet implemented.

Source files retain the corresponding upstream SPDX identifiers. The upstream
Business Source License is in `LICENSE-BUSL-1.1`.

Current verified implementations: LiquityMath, AddressesRegistry, GasPool,
DefaultPool, CollSurplusPool, ActivePool, BoldToken (including ERC20Permit and
EIP712), SortedTroves (including batch operations), and TroveNFT. The current suite
passes 70 EVM tests plus 2 Fe tests. `PoolSystem.t.sol`
deploys and connects the actual Fe registry, token and pools, and compares
collateral redistribution, surplus claims and interest minting with Solidity.
BorrowerOperations/TroveManager and StabilityPool are not yet ported; this pool
workflow is not a complete borrowing/liquidation deployment.

Use `build/protocol/*.abi.json` for protocol integration after `scripts/test.sh`.
The ABI export validates every function signature, return shape and emitted event
against Solidity. It accounts explicitly for pure implementations of view getters,
the flat seven-value EIP712 domain return, static tuple output metadata,
conservative STATICCALL capability metadata, and unused reference declarations.
Original Fe compiler ABIs remain in `build/*.abi.json`; the audit is recorded in
`tests/results/abi-audit.json`. Runtime parity is checked separately by the EVM tests.

The full outstanding source inventory is in `port_status.json` (102 core/helper
source files) and `governance_status.json` (27 governance source files). Pinned
OpenZeppelin, Solady and governance trees are checked for source drift before tests.

SortedTroves tests compare exact list and batch storage, search hints, equal-rate
ordering, access control and stateful randomized operations. TroveNFT tests cover
ERC721 events and approvals, callback rollback and reentrancy, constructor strings,
metadata dependency calls and unpadded transfer calldata. Its TroveManager and
MetadataNFT dependencies remain test doubles; actual SVG/JSON rendering is pending.

The local compiler integrates existing upstream PRs #1592 and #1587; their 10 and
14 dedicated regression tests pass. See `COMPILER_FIXES.md`. The latest complete
validation log and source/artifact hashes are `tests/results/sorted-nft.log` and
`tests/results/sorted-nft.json`. After a new successful logged test run, record its
provenance with `python3 scripts/record_validation.py <log-path>` before edits.
