# Current work state

The complete Liquity V2 port goal remains active. This is a verified partial
contract system, not the complete borrowing protocol.

## Toolchain and references

- `reference/bold`: `c8a5a4ee2e9dc024905856b6698a77d849c68c7e`.
- `toolchain/fe`, branch `liquity-v2-integration`: upstream/master
  `f00132a97429f966804d70c40206ef40ebca6960` plus PRs #1592 and #1587.
- Integration commit `5903581eecd9ce0edf78884feeef087729973e5d`.
- Upstream/master was rechecked with git ls-remote during the sorted-list/NFT validation and
  still points to the same base commit. Compiler source worktree is clean.
- PR #1575 was tested on a separate investigation branch and NOT integrated.
  The diagnosed storage-borrow-across-CALL pattern is deliberately rejected.
- Local release compiler rebuilt after integrating #1587. Both upstream fix
  regression suites pass (10 + 14 tests). No newly authored compiler fixes.
- No builds/tests are still running.
- Sandbox shell currently fails with `bwrap: loopback: Failed RTM_NEWADDR`;
  approved `require_escalated` shell calls have been used throughout.

## Verified current implementation

- LiquityMath: every function and LiquityBase interest arithmetic.
- AddressesRegistry: validation, all getters, one-time registration, ownership,
  events, malformed ABI rejection.
- GasPool: reference approval behavior, including false approval return values.
- DefaultPool: debt/collateral transfers, access control, SafeERC20 and rollback.
- CollSurplusPool: per-account surplus and real token claims, events and rollback.
- ActivePool: all functions, ceil aggregate interest, batch fees, upfront fees,
  yield split/minting, shutdown periods, collateral transfers and access control.
- BoldToken: all functions, branch/registry permissions, mint/burn/pool movements,
  ERC20 balances/allowances, EIP2612 permits, EIP712 domains and replay protection.
- SortedTroves: full individual/batch insertion, removal, relocation, hint search,
  equal-rate ordering, errors, authorization and Solidity-compatible storage.
- TroveNFT: full ERC721 behavior, callbacks/reentrancy, constructor name/symbol,
  dynamic strings, latest-data and metadata dependency calls, events and errors.
- TroveChange fields/ABI are integrated into ActivePool; LatestTroveData fields/ABI
  are consumed by TroveNFT. LatestBatchData is still only a field definition.

`./scripts/test.sh` passes 2 Fe tests and 70 EVM tests (1,024 runs per fuzz test,
plus cached passing regression inputs where present). See `tests/results/sorted-nft.*`.
The connected PoolSystem test uses the actual Fe registry, BOLDToken, ActivePool,
DefaultPool, CollSurplusPool and GasPool together. Collateral token and SP reward
receiver are Solidity test doubles; BO/TM operations are driven by the test.
It checks redistribution transfers, surplus claims and a year of real BOLD yield
minting against the same Solidity system. This does NOT establish complete Trove
or StabilityPool workflows yet.

`build/protocol/*.abi.json` exports audited Solidity-compatible ABI metadata.
`build/*.abi.json` retains raw compiler ABIs. The only return layout adaptation is
BoldToken.eip712Domain: seven flat return values via encode_abi_payload/RawOps.
SortedTroves static tuple outputs use identical flat runtime encoding. Its two
read-only external-call getters and TroveNFT.tokenURI use STATICCALL despite the
compiler's conservative nonpayable Call-capability metadata. These refinements,
unused reference declarations and pure/view metadata differences are explicit in
`scripts/export_abi.py`; see `tests/results/abi-audit.json`.

## Next implementation work

1. MetadataNFT and its full SVG/JSON/asset dependencies, plus manager helpers and
   LiquityBase shared configuration. TroveNFT currently uses mocked manager and
   renderer dependencies in its differential tests; rendered metadata is pending.
2. Full TroveManager and BorrowerOperations: preserve individual/batch debt,
   shares, interest, management fees, rates, liquidation/redistribution and
   redemptions. Never substitute a simplified CDP implementation.
3. StabilityPool, CollateralRegistry, oracle feeds/shutdown, hints/getters,
   redemption helpers and zappers.
4. Governance implementation/integration. `governance_status.json` now contains
   all 27 pinned V2-gov/src source files; main inventory has 102 bold sources.
5. Complete multi-branch Fe deployment, user lifecycle, liquidations/redemptions,
   SP compounding/yield, differential/invariant tests, ABI gates, and final audit.

Potential future shared-code cleanup: `revert_texts.fe` holds exact reference
strings as byte literals because inline Fe strings are limited to 31 bytes.
New handlers must use the right Solidity error payloads, rather than replacing
these with empty require reverts. Long tuple return lists may require explicit
flat ABI encoding; always test from Solidity and include the metadata gate.

Compiler fixes, if newly authored, must each have their own branch, regression
tests and newsfragment, then be integrated and recorded in COMPILER_FIXES.md.

SortedTroves fuzz harnesses must mirror BorrowerOperations: reinsert before
changing TroveManager's reported rate. Updating the rate first can invalidate
self-hints and break ordering in both Fe and Solidity. A deterministic regression
retains the sequence that exposed this harness error.
