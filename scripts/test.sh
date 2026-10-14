#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
FE="$PWD/toolchain/fe/target/release/fe"
python3 scripts/verify_reference.py
python3 scripts/verify_compiler.py --binary
python3 -m unittest discover -s tests -p "test_*.py"
"$FE" check .
"$FE" test .
"$FE" build . -O 1 --out-dir build
forge test -vv
python3 scripts/export_abi.py
