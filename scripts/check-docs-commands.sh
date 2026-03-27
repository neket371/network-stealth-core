#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOC_FILES=(
    README.md
    README.ru.md
    docs/en/FIELD-VALIDATION.md
    docs/ru/FIELD-VALIDATION.md
    docs/en/MAINTAINER-LAB.md
    docs/ru/MAINTAINER-LAB.md
    docs/en/OPERATIONS.md
    docs/ru/OPERATIONS.md
    docs/en/TROUBLESHOOTING.md
    docs/ru/TROUBLESHOOTING.md
    .github/CONTRIBUTING.md
    .github/CONTRIBUTING.ru.md
)

VALID_ACTIONS='install|add-clients|add-keys|update|repair|migrate-stealth|diagnose|doctor|rollback|uninstall|status|logs|check-update'
SELF_HOSTED_WORKFLOW=".github/workflows/self-hosted-smoke.yml"

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
done < <(search_docs_regex '(^|[[:space:]`])(sudo[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*bash[[:space:]].*xray-reality\.sh')

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

check_pinned_bootstrap_order() {
    local file="$1"
    local pinned_line tag_line floating_line
    pinned_line="$(grep -n 'XRAY_REPO_COMMIT=<full_commit_sha>' "$file" | head -n1 | cut -d: -f1 || true)"
    tag_line="$(grep -nE 'XRAY_REPO_REF=v[0-9]+\.[0-9]+\.[0-9]+' "$file" | head -n1 | cut -d: -f1 || true)"
    floating_line="$(grep -n '^sudo bash /tmp/xray-reality.sh install$' "$file" | head -n1 | cut -d: -f1 || true)"

    if [[ -z "$pinned_line" || -z "$tag_line" || -z "$floating_line" ]]; then
        echo "docs command contract fail: missing bootstrap examples in ${file}" >&2
        fail=1
        return 0
    fi

    if ((pinned_line > tag_line)); then
        echo "docs command contract fail: commit-pinned bootstrap must appear before tag-pinned bootstrap in ${file}" >&2
        fail=1
    fi

    if ((tag_line > floating_line)); then
        echo "docs command contract fail: tag-pinned bootstrap must appear before floating bootstrap in ${file}" >&2
        fail=1
    fi
}

check_pinned_bootstrap_order README.md
check_pinned_bootstrap_order README.ru.md

for file in docs/en/FAQ.md docs/ru/FAQ.md docs/en/OPERATIONS.md docs/ru/OPERATIONS.md; do
    if ! grep -q 'XRAY_REPO_REF=v<release-tag>' "$file"; then
        echo "docs command contract fail: missing tag-pinned bootstrap guidance in ${file}" >&2
        fail=1
    fi
done

for file in docs/en/OPERATIONS.md docs/ru/OPERATIONS.md docs/en/TROUBLESHOOTING.md docs/ru/TROUBLESHOOTING.md; do
    if grep -q 'export xray\.browser\.dialer=' "$file"; then
        echo "docs command contract fail: invalid dotted export guidance in ${file}" >&2
        fail=1
    fi
    if ! grep -q "env 'xray.browser.dialer=127.0.0.1:11050'" "$file"; then
        echo "docs command contract fail: missing shell-safe browser dialer guidance in ${file}" >&2
        fail=1
    fi
done

for file in README.md README.ru.md docs/en/OPERATIONS.md docs/ru/OPERATIONS.md docs/en/INDEX.md docs/ru/INDEX.md; do
    if ! grep -q 'FIELD-VALIDATION.md' "$file"; then
        echo "docs command contract fail: missing field-validation link in ${file}" >&2
        fail=1
    fi
done

for file in docs/en/MAINTAINER-LAB.md docs/ru/MAINTAINER-LAB.md .github/CONTRIBUTING.md .github/CONTRIBUTING.ru.md; do
    if ! grep -q 'Nightly Smoke' "$file"; then
        echo "docs command contract fail: missing Nightly Smoke regular-evidence wording in ${file}" >&2
        fail=1
    fi
    if ! grep -q 'self-hosted-smoke.yml' "$file"; then
        echo "docs command contract fail: missing manual self-hosted workflow reference in ${file}" >&2
        fail=1
    fi
done

if ! grep -q '^name: Self-hosted Smoke (manual)$' "$SELF_HOSTED_WORKFLOW"; then
    echo "docs command contract fail: self-hosted workflow must be explicitly marked manual" >&2
    fail=1
fi
if ! grep -q 'Regular self-hosted evidence lives in Nightly Smoke; this workflow is manual/on-demand only.' "$SELF_HOSTED_WORKFLOW"; then
    echo "docs command contract fail: self-hosted workflow must point to Nightly Smoke as the regular evidence path" >&2
    fail=1
fi

if ((fail != 0)); then
    exit 1
fi

echo "docs command contracts: ok"
