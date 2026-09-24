# Metadata concatenation compile-time investigation

The initial heterogeneous `Fragments` tuple adapters made the renderer build
very slow. A standalone `ConcatProbe` using only a two-element tuple compiled
quickly when the larger unused tuple implementations were removed. Keeping
all 2–16 adapters reproduced the slow compilation independently of the renderer.
Replacing many raw-pointer stores with a shared loop improved the standalone
case, but uniform `[Bytes; N]` inputs compiled substantially faster still.

The preserved source is `metadata_tuple_concat.fe`. To investigate separately:

```sh
toolchain/fe/target/release/fe build tests/repros/metadata_tuple_concat.fe --standalone -O 1 --out-dir /tmp/liquity-tuple-repro
```

These observations used compiler integration commit
`5903581eecd9ce0edf78884feeef087729973e5d`. They do not establish an infinite loop
or identify the responsible compiler pass. The old project builds were explicitly
terminated after adopting the fast-compiling replacement, not treated as crashed
because a polling window expired. Debugger and perf attachment were unavailable
under the host's process-observation restrictions.

The production port now uses `src/metadata_concat.fe` with pairwise concatenation.
The intermediate uniform-byte-array implementation still compiled slowly. This is an implementation choice; no compiler source fix,
submission branch, or new compiler newsfragment was authored for it.

## PR #1585 evaluation

Existing upstream PR #1585 was integrated as compiler commit
`ce277a26962d60fa0c5fa58ef2219313a922903b`. All 218 HIR unit tests pass,
as do the existing 24 ABI/event execution regressions. The uniform-array project and tuple
probe remained busy and were explicitly stopped after a full pairwise alternative
compiled successfully. No speedup is attributed to PR #1585 alone.

Although attaching to an existing process was blocked, starting a fresh child
under GDB works without changing host settings. A 20-second sample of the tuple
probe on this compiler was in `AccessFootprint::overlap`, called by
`OpaqueWrite::contents`, `BorrowState::write_regions`, and `Borrowck::solve`.
A separate 25-second full-project ABI sample was still in semantic admission
and type normalization. These individual samples locate work at those instants;
they do not establish which phase dominates the complete build.

A 60-second full-project sample was in `BorrowState::write_regions` and
`Guard::substitute`, reached through the borrow checker. The pairwise renderer
compiled successfully and passes the complete 96 EVM / 2 Fe test suite. It uses
a constructor-created geometry/static-SVG companion to meet EIP-170 without
changing the protocol ABI or the callers of token/asset dependencies.
