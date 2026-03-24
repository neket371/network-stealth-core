#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_FILE="$ROOT_DIR/data/domains/catalog.json"
OUT_DIR="$ROOT_DIR"

while (($# > 0)); do
    case "$1" in
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "usage: scripts/generate-domain-fallbacks.sh [--out-dir dir]" >&2
            exit 1
            ;;
    esac
done

if ! command -v jq > /dev/null 2>&1; then
    echo "generate-domain-fallbacks: jq is required in PATH" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"

TIERS_OUT="$OUT_DIR/domains.tiers"
POOLS_OUT="$OUT_DIR/sni_pools.map"

jq -r '
    def tier_domains($items):
        $items[]
        | select(type == "object" and (.domain? | type == "string"))
        | .domain;

    [
      "# Domain tiers for Network Stealth Core.",
      "# Generated from data/domains/catalog.json. Edit catalog.json, not this file.",
      ""
    ]
    + (
      if (.tiers.priority // []) | length > 0 then
        ["[priority]"] + ((.tiers.priority // []) | map(tostring)) + [""]
      else
        []
      end
    )
    + (
      .tiers
      | to_entries
      | map(select(.key != "priority"))
      | map(["[" + .key + "]"] + ([tier_domains(.value)] | flatten) + [""])
      | flatten
    )
    | .[]
' "$CATALOG_FILE" > "$TIERS_OUT"

jq -r '
    .tiers
    | to_entries
    | map(select(.key != "priority"))
    | map(.value[])
    | flatten
    | map(select(type == "object" and (.domain? | type == "string")))
    | reduce .[] as $entry ([]; if any(.[]; .domain == $entry.domain) then . else . + [$entry] end)
    | map("\(.domain)=\((.sni_pool // [.domain]) | join(" "))")
    | .[]
' "$CATALOG_FILE" > "$POOLS_OUT"
