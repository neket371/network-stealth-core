#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

load_existing_ports_from_config() {
    mapfile -t PORTS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | select(.port != null)
        | .port' "$XRAY_CONFIG")
    mapfile -t PORTS_V6 < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "") | test(":"))
        | select(.port != null)
        | .port' "$XRAY_CONFIG")
    NUM_CONFIGS=${#PORTS[@]}
    local max_configs
    max_configs=$(max_configs_for_tier "$DOMAIN_TIER")
    if ((NUM_CONFIGS < 1 || NUM_CONFIGS > max_configs)); then
        log WARN "Загружено конфигураций: ${NUM_CONFIGS} (лимит ${DOMAIN_TIER}: ${max_configs}) — возможна ошибка в конфиге"
    fi
    HAS_IPV6=false
    if ((${#PORTS_V6[@]} > 0)); then
        HAS_IPV6=true
    fi
    : "${HAS_IPV6}"
}

load_existing_metadata_from_config() {
    mapfile -t CONFIG_DOMAINS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.dest // empty' "$XRAY_CONFIG" | sed 's/:.*//')
    mapfile -t CONFIG_SNIS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_CONFIG")
    mapfile -t CONFIG_FPS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.fingerprint // "chrome"' "$XRAY_CONFIG")
    mapfile -t CONFIG_GRPC_SERVICES < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.grpcSettings.serviceName // .streamSettings.httpSettings.path // "-" ' "$XRAY_CONFIG")
}

load_keys_from_config() {
    mapfile -t UUIDS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .settings.clients[0].id // empty' "$XRAY_CONFIG")
    mapfile -t SHORT_IDS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_CONFIG")
    mapfile -t PRIVATE_KEYS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.privateKey // empty' "$XRAY_CONFIG")
}

load_keys_from_keys_file() {
    local keys_file="${XRAY_KEYS}/keys.txt"
    [[ -f "$keys_file" ]] || return 1

    PRIVATE_KEYS=()
    PUBLIC_KEYS=()
    UUIDS=()
    SHORT_IDS=()

    local line value
    while IFS= read -r line; do
        case "$line" in
            "Private Key:"*)
                value=$(trim_ws "${line#Private Key:}")
                PRIVATE_KEYS+=("$value")
                ;;
            "Public Key:"*)
                value=$(trim_ws "${line#Public Key:}")
                PUBLIC_KEYS+=("$value")
                ;;
            "UUID:"*)
                value=$(trim_ws "${line#UUID:}")
                UUIDS+=("$value")
                ;;
            "ShortID:"*)
                value=$(trim_ws "${line#ShortID:}")
                SHORT_IDS+=("$value")
                ;;
            *) ;;
        esac
    done < "$keys_file"
    return 0
}

load_keys_from_clients_file() {
    local client_file="${XRAY_KEYS}/clients.txt"
    [[ -f "$client_file" ]] || return 1

    PUBLIC_KEYS=()
    UUIDS=()
    SHORT_IDS=()

    local line uuid params pbk sid
    while IFS= read -r line; do
        [[ "$line" == vless://* ]] || continue
        [[ "$line" == *"@["* ]] && continue

        uuid="${line#vless://}"
        uuid="${uuid%%@*}"
        params="${line#*\?}"
        params="${params%%#*}"
        pbk=$(get_query_param "$params" "pbk" || true)
        sid=$(get_query_param "$params" "sid" || true)

        UUIDS+=("$uuid")
        PUBLIC_KEYS+=("$pbk")
        SHORT_IDS+=("$sid")
    done < "$client_file"
    return 0
}

maybe_reuse_existing_config() {
    if [[ "$REUSE_EXISTING" != true ]]; then
        return 1
    fi
    if [[ ! -f "$XRAY_CONFIG" || ! -x "$XRAY_BIN" ]]; then
        return 1
    fi
    if ! xray_config_test_ok "$XRAY_CONFIG"; then
        log WARN "Существующая конфигурация невалидна, пересоздаём"
        return 1
    fi

    load_existing_ports_from_config
    if [[ $NUM_CONFIGS -lt 1 ]]; then
        return 1
    fi

    load_existing_metadata_from_config
    load_keys_from_config
    if ! load_keys_from_keys_file; then
        load_keys_from_clients_file || true
    fi

    REUSE_EXISTING_CONFIG=true
    : "${REUSE_EXISTING_CONFIG}"
    NON_INTERACTIVE=true
    ASSUME_YES=true
    log OK "Используем существующую валидную конфигурацию (без перегенерации)"
    return 0
}
