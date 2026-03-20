#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob

if ! command -v bats > /dev/null 2>&1; then
    echo "bats quality check: bats is required in PATH" >&2
    exit 2
fi

FILES=()
if (($# > 0)); then
    FILES=("$@")
else
    FILES=("$ROOT_DIR"/tests/bats/*.bats)
fi

if ((${#FILES[@]} == 0)); then
    echo "bats quality check: no bats files discovered" >&2
    exit 1
fi

fail=0
for file in "${FILES[@]}"; do
    [[ -f "$file" ]] || continue
    if ! bats --count "$file" > /dev/null; then
        echo "bats quality check fail: parser rejected $file" >&2
        fail=1
    fi
done

if ((fail != 0)); then
    exit 1
fi

echo "bats quality check: ok"
