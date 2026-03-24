#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_FILE="$ROOT_DIR/data/domains/catalog.json"
TIERS_FILE="$ROOT_DIR/domains.tiers"
POOLS_FILE="$ROOT_DIR/sni_pools.map"
GENERATOR_SCRIPT="$ROOT_DIR/scripts/generate-domain-fallbacks.sh"

if ! command -v jq > /dev/null 2>&1; then
    echo "domain-data-check: jq is required in PATH" >&2
    exit 2
fi
if [[ ! -f "$GENERATOR_SCRIPT" ]]; then
    echo "domain-data-check: generator script is missing: $GENERATOR_SCRIPT" >&2
    exit 2
fi

fail=0

while IFS='=' read -r domain values; do
    domain="${domain//$'\r'/}"
    [[ -n "${domain// /}" ]] || continue
    [[ "$domain" =~ ^[[:space:]]*# ]] && continue
    duplicate="$(printf '%s\n' "$values" | tr ' ' '\n' | sed '/^$/d' | sort | uniq -d | head -n 1 || true)"
    if [[ -n "$duplicate" ]]; then
        echo "domain-data-check: duplicate SNI '$duplicate' in map pool '$domain'" >&2
        fail=1
    fi
done < "$POOLS_FILE"

while IFS=$'\t' read -r tier domain duplicate; do
    echo "domain-data-check: duplicate SNI '$duplicate' in catalog pool '${tier}/${domain}'" >&2
    fail=1
done < <(
    jq -r '
        .tiers
        | to_entries[]
        | .key as $tier
        | .value[]
        | select(type == "object" and (.domain? | type == "string"))
        | .domain as $domain
        | (.sni_pool // [])
        | group_by(.)
        | map(select(length > 1) | .[0])
        | .[]
        | [$tier, $domain, .]
        | @tsv
    ' "$CATALOG_FILE"
)

declare -A catalog_domains=()
while IFS=$'\t' read -r tier domain; do
    tier="${tier//$'\r'/}"
    domain="${domain//$'\r'/}"
    catalog_domains["$tier|$domain"]=1
done < <(
    jq -r '
        .tiers
        | to_entries[]
        | .key as $tier
        | .value[]
        | select(type == "object" and (.domain? | type == "string"))
        | [$tier, .domain]
        | @tsv
    ' "$CATALOG_FILE"
)

declare -A catalog_priority_domains=()
while IFS= read -r domain; do
    domain="${domain//$'\r'/}"
    [[ -n "$domain" ]] || continue
    catalog_priority_domains["$domain"]=1
done < <(jq -r '.tiers.priority[]?' "$CATALOG_FILE")

declare -A map_domains=()
while IFS='=' read -r domain _; do
    domain="${domain//$'\r'/}"
    [[ -n "${domain// /}" ]] || continue
    [[ "$domain" =~ ^[[:space:]]*# ]] && continue
    map_domains["$domain"]=1
done < "$POOLS_FILE"

current_tier=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^\[([A-Za-z0-9_.-]+)\]$ ]]; then
        current_tier="${BASH_REMATCH[1]}"
        continue
    fi
    [[ -n "$current_tier" ]] || continue
    domain="$line"
    if [[ "$current_tier" == "priority" ]]; then
        if [[ -z "${catalog_priority_domains["$domain"]:-}" ]]; then
            echo "domain-data-check: domains.tiers contains 'priority/${domain}' missing in catalog.json priority list" >&2
            fail=1
        fi
    elif [[ -z "${catalog_domains["$current_tier|$domain"]:-}" ]]; then
        echo "domain-data-check: domains.tiers contains '${current_tier}/${domain}' missing in catalog.json" >&2
        fail=1
    fi
    if [[ -z "${map_domains["$domain"]:-}" ]]; then
        echo "domain-data-check: domains.tiers contains '${current_tier}/${domain}' missing in sni_pools.map" >&2
        fail=1
    fi
done < "$TIERS_FILE"

if ((fail != 0)); then
    exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup_domain_data_tmp() {
    rm -rf "$tmp_dir"
}
trap cleanup_domain_data_tmp EXIT

"$GENERATOR_SCRIPT" --out-dir "$tmp_dir"
if ! diff -u "$tmp_dir/domains.tiers" "$TIERS_FILE" > /dev/null; then
    echo "domain-data-check: domains.tiers drifted from catalog.json; run scripts/generate-domain-fallbacks.sh" >&2
    exit 1
fi
if ! diff -u "$tmp_dir/sni_pools.map" "$POOLS_FILE" > /dev/null; then
    echo "domain-data-check: sni_pools.map drifted from catalog.json; run scripts/generate-domain-fallbacks.sh" >&2
    exit 1
fi

echo "domain-data-check: ok"
