#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOC_FILES=(
    README.md
    README.ru.md
    docs/en/MAINTAINER-LAB.md
    docs/ru/MAINTAINER-LAB.md
    docs/en/OPERATIONS.md
    docs/ru/OPERATIONS.md
    docs/en/TROUBLESHOOTING.md
    docs/ru/TROUBLESHOOTING.md
    .github/CONTRIBUTING.md
    .github/CONTRIBUTING.ru.md
)

VALID_ACTIONS='install|add-clients|add-keys|update|repair|migrate-stealth|diagnose|rollback|uninstall|status|logs|check-update'

fail=0

search_docs_regex() {
    local pattern="$1"
    if command -v rg > /dev/null 2>&1; then
        rg -n --no-heading "$pattern" "${DOC_FILES[@]}" || true
    else
        grep -n -E -- "$pattern" "${DOC_FILES[@]}" 2> /dev/null || true
    fi
}

while IFS=: read -r file line text; do
    normalized="$(sed 's/`//g; s/[[:space:]]\+/ /g' <<< "$text")"

    if [[ "$normalized" =~ xray-reality\.sh[^A-Za-z0-9-]+(${VALID_ACTIONS})([^A-Za-z0-9_-]|$) ]]; then
        continue
    fi
    if [[ "$normalized" =~ xray-reality\.sh[^A-Za-z0-9-]+(-h|--help)([^A-Za-z0-9_-]|$) ]]; then
        continue
    fi

    echo "docs command contract fail: unresolved xray-reality command at ${file}:${line}" >&2
    echo "  ${text}" >&2
    fail=1
done < <(search_docs_regex '(^|[[:space:]`])(sudo[[:space:]]+)?bash[[:space:]].*xray-reality\.sh')

declare -A make_targets=()
while IFS= read -r target; do
    make_targets["$target"]=1
done < <(awk -F: '/^[A-Za-z0-9_.-]+:/{print $1}' Makefile)

while IFS=: read -r file line text; do
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        if [[ -z "${make_targets[$target]:-}" ]]; then
            echo "docs command contract fail: unknown make target '${target}' at ${file}:${line}" >&2
            fail=1
        fi
    done < <(grep -oE 'make[[:space:]]+[A-Za-z0-9_.-]+' <<< "$text" | awk '{print $2}')
done < <(search_docs_regex 'make[[:space:]]+[A-Za-z0-9_.-]+')

if ((fail != 0)); then
    exit 1
fi

echo "docs command contracts: ok"
