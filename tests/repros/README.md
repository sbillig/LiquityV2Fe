# Investigation fixtures

`storage_call.fe` is intentionally rejected by Fe. This is the documented rule
against keeping a native storage borrow alive across an external CALL, which can
reenter the contract. It is not a compiler regression. The ActivePool port ends
its accounting borrows before token/reward calls and resumes storage operations
afterwards, preserving the reference's read/write order.

PR #1575 was tested on `liquity-v2-borrow-investigation`; it does not change this
behavior and was not included in the integration compiler.
