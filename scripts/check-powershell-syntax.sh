#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POWERSHELL_BIN="${POWERSHELL_BIN:-}"

if [[ -z "$POWERSHELL_BIN" ]]; then
    if command -v pwsh > /dev/null 2>&1; then
        POWERSHELL_BIN="pwsh"
    elif command -v powershell > /dev/null 2>&1; then
        POWERSHELL_BIN="powershell"
    else
        echo "powershell syntax check: pwsh or powershell is required in PATH" >&2
        exit 2
    fi
fi

"$POWERSHELL_BIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT_DIR/scripts/windows/check-powershell-syntax.ps1" "$@"
