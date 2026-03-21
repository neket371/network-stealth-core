#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

export_capabilities_json() {
    local export_dir="$1"
    local out_file="$2"
    local out_parent
    out_parent="$(dirname "$out_file")"
    mkdir -p "$out_parent" || {
        echo "ERROR: не удалось создать каталог экспорта: $out_parent" >&2
        return 1
    }
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX") || {
        echo "ERROR: не удалось создать временный файл экспорта: $out_file" >&2
        return 1
    }
    trap 'rm -f "$tmp_out" 2>/dev/null' RETURN

    jq -n \
        --arg generated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg transport "${TRANSPORT:-xhttp}" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION}" \
        --arg contract_version "${STEALTH_CONTRACT_VERSION}" \
        --arg clients_txt "${XRAY_KEYS}/clients.txt" \
        --arg clients_links "${XRAY_KEYS}/clients-links.txt" \
        --arg clients_json "${XRAY_KEYS}/clients.json" \
        --arg raw_xray_dir "${export_dir}/raw-xray" \
        --arg raw_xray_index "${export_dir}/raw-xray-index.json" \
        --arg v2rayn "${export_dir}/v2rayn-links.json" \
        --arg nekoray "${export_dir}/nekoray-template.json" \
        --arg canary_manifest "${export_dir}/canary/manifest.json" \
        '{
            schema_version: 2,
            generated: $generated,
            transport: $transport,
            stealth_contract_version: $contract_version,
            xray_min_version: $min_version,
            formats: [
                {
                    name: "clients.txt",
                    status: "native",
                    artifact: $clients_txt,
                    xray_min_version: $min_version,
                    requires: [],
                    reason: "human-readable server-managed client summary"
                },
                {
                    name: "clients-links.txt",
                    status: "native",
                    artifact: $clients_links,
                    xray_min_version: $min_version,
                    requires: ["xhttp"],
                    reason: "quick-copy vless links for recommended and rescue variants plus raw xray references"
                },
                {
                    name: "clients.json",
                    status: "native",
                    artifact: $clients_json,
                    xray_min_version: $min_version,
                    requires: ["schema_v3"],
                    reason: "schema v3 source of truth for generated variants"
                },
                {
                    name: "raw-xray",
                    status: "native",
                    artifact: $raw_xray_dir,
                    index: $raw_xray_index,
                    xray_min_version: $min_version,
                    requires: ["xhttp", "vless-encryption", "xtls-rprx-vision"],
                    reason: "per-variant xray client json for xhttp self-check and direct import"
                },
                {
                    name: "v2rayn-links",
                    status: "link-only",
                    artifact: $v2rayn,
                    xray_min_version: $min_version,
                    requires: ["xhttp"],
                    reason: "vless links only; raw xray json remains the canonical xhttp artifact"
                },
                {
                    name: "nekoray-template",
                    status: "link-only",
                    artifact: $nekoray,
                    xray_min_version: $min_version,
                    requires: ["xhttp"],
                    reason: "template contains links and references to raw xray json"
                },
                {
                    name: "canary-bundle",
                    status: "native",
                    artifact: $canary_manifest,
                    xray_min_version: $min_version,
                    requires: ["raw-xray", "browser-dialer-for-emergency"],
                    reason: "field-measurement bundle for recommended, rescue, and emergency variants"
                },
                {
                    name: "sing-box",
                    status: "unsupported",
                    artifact: null,
                    xray_min_version: $min_version,
                    requires: ["xhttp", "vless-encryption", "xtls-rprx-vision"],
                    reason: "not generated for the strongest-direct contract to avoid misleading degraded templates"
                },
                {
                    name: "clash-meta",
                    status: "unsupported",
                    artifact: null,
                    xray_min_version: $min_version,
                    requires: ["xhttp", "vless-encryption", "xtls-rprx-vision"],
                    reason: "not generated for the strongest-direct contract to avoid misleading degraded templates"
                }
            ]
        }' > "$tmp_out" || return 1

    mv "$tmp_out" "$out_file"
    trap - RETURN
}

export_capabilities_notes_from_json() {
    local capabilities_file="$1"
    local out_file="$2"
    local out_parent
    out_parent="$(dirname "$out_file")"
    mkdir -p "$out_parent" || {
        echo "ERROR: не удалось создать каталог экспорта: $out_parent" >&2
        return 1
    }
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX") || {
        echo "ERROR: не удалось создать временный файл экспорта: $out_file" >&2
        return 1
    }
    trap 'rm -f "$tmp_out" 2>/dev/null' RETURN

    {
        printf 'network stealth core export notes\n'
        printf '===============================\n\n'
        printf 'transport: %s\n\n' "${TRANSPORT:-xhttp}"
        printf 'capabilities:\n'
        jq -r '.formats[]
            | "- " + .name + ": " + .status
              + (if (.artifact // "") != "" then " -> " + .artifact else "" end)
              + "\n  xray min: " + (.xray_min_version // "n/a")
              + "\n  requires: " + ((.requires // []) | join(", "))
              + "\n  reason: " + (.reason // "n/a")
        ' "$capabilities_file"
    } > "$tmp_out" || return 1

    mv "$tmp_out" "$out_file"
    trap - RETURN
}
