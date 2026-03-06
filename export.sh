#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/lib/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

CONFIG_SHARED_HELPERS_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SHARED_HELPERS_MODULE"
fi

validate_export_json_schema() {
    local file="$1"
    local kind="$2"

    if [[ ! -f "$file" ]]; then
        log ERROR "Файл экспорта не найден: $file"
        return 1
    fi

    case "$kind" in
        json)
            jq empty "$file" > /dev/null 2>&1 || {
                log ERROR "Некорректный JSON в экспорте: $file"
                return 1
            }
            ;;
        text)
            [[ -s "$file" ]] || {
                log ERROR "Пустой текстовый экспорт: $file"
                return 1
            }
            ;;
        *)
            log ERROR "Неизвестный тип schema проверки: ${kind}"
            return 1
            ;;
    esac

    return 0
}

export_raw_xray_index() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX")

    jq '{
        generated,
        transport,
        schema_version,
        configs: [
            .configs[] | {
                name,
                domain,
                sni,
                fingerprint,
                transport,
                transport_endpoint,
                recommended_variant,
                variants: [
                    .variants[] | {
                        key,
                        label,
                        note,
                        mode,
                        vless_v4,
                        vless_v6,
                        xray_client_file_v4,
                        xray_client_file_v6
                    }
                ]
            }
        ]
    }' "$json_file" > "$tmp_out"

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    mv "$tmp_out" "$out_file"
    log OK "Индекс raw Xray сохранён: $out_file"
}

export_v2rayn_fragment_template() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX")

    jq '{
        generated,
        transport,
        profiles: [
            .configs[] as $cfg
            | ($cfg.variants // [])[]
            | {
                name: ($cfg.name + " / " + (.label // .key // "standard")),
                config_name: $cfg.name,
                domain: $cfg.domain,
                server: .vless_v4,
                transport: ($cfg.transport // .transport),
                transport_endpoint: ($cfg.transport_endpoint // .transport_endpoint),
                mode: .mode,
                vless_link: .vless_v4,
                vless_link_ipv6: .vless_v6,
                raw_xray_file_v4: .xray_client_file_v4,
                raw_xray_file_v6: .xray_client_file_v6
            }
        ]
    }' "$json_file" > "$tmp_out"

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    mv "$tmp_out" "$out_file"
    log OK "Шаблон ссылок v2rayN сохранён: $out_file"
}

export_nekoray_fragment_template() {
    local json_file="$1"
    local out_file="$2"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX")

    jq '{
        generated,
        transport,
        note: "xhttp-first export. import vless link or open raw xray json directly.",
        profiles: [
            .configs[] as $cfg
            | ($cfg.variants // [])[]
            | {
                name: ($cfg.name + " / " + (.label // .key // "standard")),
                domain: $cfg.domain,
                sni: $cfg.sni,
                fingerprint: $cfg.fingerprint,
                transport: ($cfg.transport // .transport),
                transport_endpoint: ($cfg.transport_endpoint // .transport_endpoint),
                mode: .mode,
                vless_link: .vless_v4,
                vless_link_ipv6: .vless_v6,
                raw_xray_file_v4: .xray_client_file_v4,
                raw_xray_file_v6: .xray_client_file_v6
            }
        ]
    }' "$json_file" > "$tmp_out"

    if ! validate_export_json_schema "$tmp_out" json; then
        rm -f "$tmp_out"
        return 1
    fi
    mv "$tmp_out" "$out_file"
    log OK "Шаблон nekoray сохранён: $out_file"
}

export_compatibility_notes() {
    local out_file="$1"
    local tmp_out
    tmp_out=$(mktemp "${out_file}.tmp.XXXXXX")

    cat > "$tmp_out" << EOF
network stealth core export notes
===============================

transport: ${TRANSPORT}

primary artifacts:
- ${XRAY_KEYS}/clients.txt
- ${XRAY_KEYS}/clients.json
- ${XRAY_KEYS}/export/raw-xray/
- ${XRAY_KEYS}/export/raw-xray-index.json
- ${XRAY_KEYS}/export/v2rayn-links.json
- ${XRAY_KEYS}/export/nekoray-template.json

notes:
- xhttp-first installs generate raw xray client json per variant.
- recommended xhttp mode is auto.
- rescue xhttp mode is packet-up.
- clashmeta and sing-box configs are intentionally not generated in xhttp-first mode to avoid misleading users with unsupported or degraded templates.
- legacy grpc/http2 installs still receive normalized link exports, but migrate-stealth is recommended.
EOF

    if ! validate_export_json_schema "$tmp_out" text; then
        rm -f "$tmp_out"
        return 1
    fi
    mv "$tmp_out" "$out_file"
    log OK "Compatibility notes сохранены: $out_file"
}

export_all_configs() {
    local export_dir="${XRAY_KEYS}/export"
    local json_file="${XRAY_KEYS}/clients.json"
    mkdir -p "$export_dir"

    if [[ ! -f "$json_file" ]]; then
        log WARN "clients.json не найден; экспорт пропущен"
        return 0
    fi
    if declare -F validate_clients_json_file > /dev/null 2>&1; then
        validate_clients_json_file "$json_file" || return 1
    fi

    export_raw_xray_index "$json_file" "${export_dir}/raw-xray-index.json"
    export_v2rayn_fragment_template "$json_file" "${export_dir}/v2rayn-links.json"
    export_nekoray_fragment_template "$json_file" "${export_dir}/nekoray-template.json"
    export_compatibility_notes "${export_dir}/compatibility-notes.txt"

    local -a artifacts=()
    mapfile -t artifacts < <(find "$export_dir" -mindepth 1 -maxdepth 2 -type f)
    if ((${#artifacts[@]} > 0)); then
        chmod 640 "${artifacts[@]}"
        chown "root:${XRAY_GROUP}" "${artifacts[@]}" 2> /dev/null || true
    fi
    log OK "Все форматы экспортированы в ${export_dir}/"
}
