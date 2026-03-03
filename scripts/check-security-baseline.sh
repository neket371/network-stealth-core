#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
SHELL_SCOPE=()
WORKFLOW_SCOPE=()
POWERSHELL_SCOPE=()

build_scope() {
    if command -v rg > /dev/null 2>&1; then
        mapfile -t SHELL_SCOPE < <(
            rg --files \
                -g '*.sh' \
                -g '!tests/bats/**' \
                -g '!scripts/check-security-baseline.sh'
        )
    else
        mapfile -t SHELL_SCOPE < <(
            find . -type f -name '*.sh' \
                ! -path './tests/bats/*' \
                ! -path './scripts/check-security-baseline.sh' \
                -print | sed 's#^\./##'
        )
    fi

    mapfile -t WORKFLOW_SCOPE < <(
        find .github/workflows -type f -name '*.yml' -print 2> /dev/null | sed 's#^\./##'
    )
    if command -v rg > /dev/null 2>&1; then
        mapfile -t POWERSHELL_SCOPE < <(rg --files -g '*.ps1')
    else
        mapfile -t POWERSHELL_SCOPE < <(
            find . -type f -name '*.ps1' -print 2> /dev/null | sed 's#^\./##'
        )
    fi

    if ((${#SHELL_SCOPE[@]} == 0)); then
        echo "security baseline fail: shell scope is empty" >&2
        exit 1
    fi
}

search_regex() {
    local pattern="$1"
    shift
    if command -v rg > /dev/null 2>&1; then
        rg -n --no-heading -e "$pattern" "$@" || true
    else
        grep -R -n -E -- "$pattern" "$@" 2> /dev/null || true
    fi
}

search_fixed() {
    local pattern="$1"
    shift
    if command -v rg > /dev/null 2>&1; then
        rg -n --no-heading -F "$pattern" "$@" || true
    else
        grep -R -n -F -- "$pattern" "$@" 2> /dev/null || true
    fi
}

check_absent() {
    local pattern="$1"
    local scope_desc="$2"
    shift 2
    local matches
    matches="$(search_regex "$pattern" "$@")"
    if [[ -n "$matches" ]]; then
        echo "security baseline fail: found forbidden pattern (${scope_desc}): ${pattern}" >&2
        printf '%s\n' "$matches" >&2
        fail=1
    fi
}

check_absent_fixed() {
    local pattern="$1"
    local scope_desc="$2"
    shift 2
    local matches
    matches="$(search_fixed "$pattern" "$@")"
    if [[ -n "$matches" ]]; then
        echo "security baseline fail: found forbidden pattern (${scope_desc}): ${pattern}" >&2
        printf '%s\n' "$matches" >&2
        fail=1
    fi
}

check_present_fixed() {
    local pattern="$1"
    local scope_desc="$2"
    shift 2
    local matches
    matches="$(search_fixed "$pattern" "$@")"
    if [[ -z "$matches" ]]; then
        echo "security baseline fail: missing required pattern (${scope_desc}): ${pattern}" >&2
        fail=1
    fi
}

build_scope

check_absent_fixed 'mktemp -u' 'race-prone tempfile creation' \
    "${SHELL_SCOPE[@]}"
check_absent 'DEBIAN_FRONTEND=noninteractive apt-get install' 'broken env assignment in package command' \
    modules/install/bootstrap.sh
check_absent 'trap -p' 'fragile trap parsing' \
    "${SHELL_SCOPE[@]}"

check_absent 'curl[^\n]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)\b' 'curl pipe shell' \
    "${WORKFLOW_SCOPE[@]}" "${SHELL_SCOPE[@]}"
if ((${#POWERSHELL_SCOPE[@]} > 0)); then
    check_absent '(^|[^A-Za-z0-9_])(Invoke-Expression|iex)([^A-Za-z0-9_]|$)' 'powershell dynamic eval' \
        "${POWERSHELL_SCOPE[@]}"
    check_absent 'DownloadString\([^)]*\)[[:space:]]*\|' 'powershell downloadstring pipe execution' \
        "${POWERSHELL_SCOPE[@]}"
    check_absent '(Invoke-WebRequest|iwr|curl|wget)[^\n|]*\|[[:space:]]*(Invoke-Expression|iex|powershell|pwsh)' 'powershell web download pipe execution' \
        "${POWERSHELL_SCOPE[@]}"
    check_absent '(^|[[:space:]])(-EncodedCommand|-enc)[[:space:]]+[A-Za-z0-9+/=]{16,}' 'powershell encoded command invocation' \
        "${POWERSHELL_SCOPE[@]}"
fi

check_present_fixed "atomic_write \"\$XRAY_ENV\" 0600" 'env file permissions' config.sh
check_present_fixed 'curl_fetch_text_allowlist "https://api.github.com/repos/XTLS/Xray-core/releases/latest"' 'allowlist update check' service.sh
check_present_fixed 'sanitize_systemd_value' 'systemd unit sanitization helper' service.sh
check_present_fixed "mapfile -t ports < <(tr ',[:space:]' '\\n' <<< \"\$REALITY_TEST_PORTS\" | awk 'NF')" 'health ports parser without split_list dependency' health.sh
check_present_fixed "proto-redir '=https'" 'https-only redirects in curl flows' lib.sh

while IFS=: read -r _file _line code; do
    if [[ "$code" == *"|| return 1"* ]]; then
        continue
    fi
    if [[ "$code" =~ ^[[:space:]]*if[[:space:]]*!?[[:space:]]*validate_export_json_schema[[:space:]] ]]; then
        continue
    fi
    if [[ "$code" =~ ^[[:space:]]*if[[:space:]]+validate_export_json_schema[[:space:]] ]]; then
        continue
    fi
    echo "security baseline fail: validate_export_json_schema call is not checked: ${_file}:${_line}" >&2
    fail=1
done < <(awk '/validate_export_json_schema[[:space:]]/ {print FILENAME ":" NR ":" $0}' export.sh)

if ((fail != 0)); then
    exit 1
fi

echo "security baseline check: ok"
