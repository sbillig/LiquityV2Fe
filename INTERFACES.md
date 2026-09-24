# Typed Solidity interface bindings

`src/interfaces.fe` exports the bindings in `src/interfaces/`. Names are prefixed
with `core_` or `gov_` to distinguish the two pinned upstream source trees. These
are message/event/error declarations for external calls, not implementations of
external token, DEX, oracle or reward services.

The 65 interfaces declare 517 callable methods. Each message variant has the
exact Solidity selector, and native ABI wrappers preserve non-native widths
such as uint24 and uint160. Solidity mutability is recorded beside each method;
use the corresponding Fe call/static-call capability at the call site. Solidity
struct parameters use tuples or named records; the 25 larger static records have
explicit field encoders/decoders. Dynamic values use the standard ABI types.

Regenerate from the pinned reference sources and compare before replacing files:

```sh
python3 scripts/generate_interfaces.py --output /tmp/liquity-generated-interfaces
python3 scripts/generate_interface_tests.py \
  --index /tmp/liquity-generated-interfaces/interface-index.json \
  --source-output /tmp/liquity-generated-interfaces/interfaces \
  --module-file /tmp/liquity-generated-interfaces/interfaces.fe \
  --test-output /tmp/liquity-generated-interfaces/tests
```

The generator checks source hashes against `reference_manifest.json` and builds
Solidity ABIs in an isolated temporary Foundry project. `interface-index.json`
records every method, selector, original ABI and source hash. Generated Fe selector
tests compare all 517 selectors with Solidity's method identifiers. Differential
record tests check valid values, truncation and noncanonical scalar encodings.
Protocol contract behavior is checked separately by the protocol parity/system
suites; selector tests do not claim to test external service implementations.
