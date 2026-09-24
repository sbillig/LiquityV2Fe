#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
FE="$PWD/toolchain/fe/target/release/fe"
python3 scripts/verify_reference.py
"$FE" test .
"$FE" build . -O 1 --out-dir build
forge test -vv
python3 scripts/export_abi.py
