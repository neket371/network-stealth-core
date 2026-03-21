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

env_escape_value() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\$/\\$}"
    value="${value//\`/\\\`}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    printf '"%s"' "$value"
}

write_env_kv() {
    local key="$1"
    local value="${2:-}"
    printf '%s=%s\n' "$key" "$(env_escape_value "$value")"
}

url_encode_component() {
    local raw="${1:-}"
    if command -v jq > /dev/null 2>&1; then
        printf '%s' "$raw" | jq -sRr @uri
        return 0
    fi

    local out="" i ch hex
    for ((i = 0; i < ${#raw}; i++)); do
        ch="${raw:i:1}"
        case "$ch" in
            [a-zA-Z0-9.~_-])
                out+="$ch"
                ;;
            *)
                printf -v hex '%%%02X' "'$ch"
                out+="$hex"
                ;;
        esac
    done
    printf '%s' "$out"
}

build_vless_query_params() {
    local sni="$1"
    local fp="$2"
    local pbk="$3"
    local sid="$4"
    local transport="$5"
    local endpoint="$6"
    local mode="${7:-}"

    local params=(
        "encryption=none"
        "security=reality"
        "flow=$(url_encode_component "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}")"
        "sni=$(url_encode_component "$sni")"
        "fp=$(url_encode_component "$fp")"
        "pbk=$(url_encode_component "$pbk")"
        "sid=$(url_encode_component "$sid")"
    )

    case "$transport" in
        xhttp)
            params+=(
                "type=xhttp"
                "path=$(url_encode_component "$endpoint")"
                "mode=$(url_encode_component "${mode:-auto}")"
            )
            ;;
        http2)
            params+=(
                "type=http"
                "host=$(url_encode_component "$sni")"
                "path=$(url_encode_component "$endpoint")"
                "alpn=h2"
            )
            ;;
        *)
            params+=(
                "type=grpc"
                "serviceName=$(url_encode_component "$endpoint")"
                "mode=multi"
            )
            ;;
    esac

    local IFS='&'
    printf '%s' "${params[*]}"
}

client_variant_import_hint() {
    local key="${1:-standard}"
    case "$key" in
        recommended)
            printf '%s' "обычно достаточно обычной vless-ссылки"
            ;;
        rescue)
            printf '%s' "используй, если основная ссылка не проходит"
            ;;
        emergency)
            printf '%s' "только raw xray json и browser dialer"
            ;;
        *)
            printf '%s' "импортируй raw xray json"
            ;;
    esac
}

transport_display_name() {
    local transport="${1:-${TRANSPORT:-xhttp}}"
    case "${transport,,}" in
        xhttp) printf '%s' "xhttp" ;;
        http2 | h2 | http/2) printf '%s' "http/2" ;;
        *) printf '%s' "grpc" ;;
    esac
}

transport_endpoint_label() {
    local transport="${1:-${TRANSPORT:-xhttp}}"
    case "${transport,,}" in
        xhttp) printf '%s' "xhttp path" ;;
        http2 | h2 | http/2) printf '%s' "http/2 path" ;;
        *) printf '%s' "grpc service" ;;
    esac
}

transport_is_legacy() {
    local transport="${1:-${TRANSPORT:-xhttp}}"
    [[ "${transport,,}" == "grpc" || "${transport,,}" == "http2" || "${transport,,}" == "h2" || "${transport,,}" == "http/2" ]]
}

client_link_prefix_for_tier() {
    local tier_raw="${1:-${DOMAIN_TIER:-tier_ru}}"
    local tier
    if ! tier=$(normalize_domain_tier "$tier_raw" 2> /dev/null); then
        tier="tier_ru"
    fi

    case "$tier" in
        tier_global_ms10)
            printf '%s' "GLOBAL"
            ;;
        custom)
            printf '%s' "CUSTOM"
            ;;
        *)
            printf '%s' "RU"
            ;;
    esac
}

client_fingerprint_pool_init() {
    local out_name="$1"
    local -n out_ref="$out_name"
    # shellcheck disable=SC2034 # out_ref is written via nameref for the caller.
    out_ref=("chrome" "chrome" "chrome" "firefox" "chrome" "firefox")
}
