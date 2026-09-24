# Investigation fixtures

`storage_call.fe` is intentionally rejected by Fe. This is the documented rule
against keeping a native storage borrow alive across an external CALL, which can
reenter the contract. It is not a compiler regression. The ActivePool port ends
its accounting borrows before token/reward calls and resumes storage operations
afterwards, preserving the reference's read/write order.

PR #1575 was tested on `liquity-v2-borrow-investigation`; it does not change this
behavior and was not included in the integration compiler.

`oversized_integer_literal.fe` independently demonstrates silent truncation of a
257-bit literal by the pinned compiler: its test currently passes because the
literal becomes zero. The fix branch documented in `COMPILER_FIXES.md` rejects
the source during type checking; the reproduction is intentionally outside the
protocol ingot.

`payable_return.fe` isolates the payable value-returning handler verifier failure
needed by WETHZapper. Existing upstream PR #1567 addresses it; its experimental
integration and regression results are recorded in `COMPILER_FIXES.md`.
