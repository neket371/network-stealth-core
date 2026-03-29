#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
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
    mapfile -t CONFIG_DESTS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.dest // empty' "$XRAY_CONFIG")
    mapfile -t CONFIG_SNIS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_CONFIG")
    mapfile -t CONFIG_FPS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.realitySettings.fingerprint // "chrome"' "$XRAY_CONFIG")
    mapfile -t CONFIG_TRANSPORT_ENDPOINTS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.xhttpSettings.path // .streamSettings.grpcSettings.serviceName // .streamSettings.httpSettings.path // "-" ' "$XRAY_CONFIG")
    mapfile -t CONFIG_VLESS_DECRYPTIONS < <(jq -r '.inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .settings.decryption // "none"' "$XRAY_CONFIG")

    CONFIG_PROVIDER_FAMILIES=()
    local domain
    for domain in "${CONFIG_DOMAINS[@]}"; do
        if [[ -n "$domain" ]]; then
            CONFIG_PROVIDER_FAMILIES+=("$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")")
        else
            CONFIG_PROVIDER_FAMILIES+=("")
        fi
    done

    load_existing_vless_encryptions_from_artifacts

    local first_transport
    first_transport=$(jq -r '
        .inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.network // empty
        ' "$XRAY_CONFIG" 2> /dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')
    case "$first_transport" in
        h2 | http/2) TRANSPORT="http2" ;;
        grpc | xhttp) TRANSPORT="$first_transport" ;;
        *)
            if [[ -n "$first_transport" ]]; then
                log WARN "Обнаружен нестандартный transport в config.json: ${first_transport} (используем xhttp-safe fallback)"
            fi
            TRANSPORT="xhttp"
            ;;
    esac
}

load_existing_vless_encryptions_from_artifacts() {
    local json_file="${XRAY_KEYS}/clients.json"
    local keys_file="${XRAY_KEYS}/keys.txt"
    local -a existing_encryptions=("${CONFIG_VLESS_ENCRYPTIONS[@]}")
    CONFIG_VLESS_ENCRYPTIONS=()

    local -a keys_encryptions=()
    if [[ -f "$keys_file" ]]; then
        mapfile -t keys_encryptions < <(awk -F'VLESS Encryption:[[:space:]]*' '
            /^VLESS Encryption:/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                if ($2 != "") print $2
            }
        ' "$keys_file")
    fi

    local i
    for ((i = 0; i < ${#CONFIG_DOMAINS[@]}; i++)); do
        local encryption=""
        local raw_file=""
        if [[ -f "$json_file" ]]; then
            encryption=$(jq -r --argjson idx "$i" '.configs[$idx].vless_encryption // empty' "$json_file" 2> /dev/null || true)
            encryption=$(trim_ws "${encryption//$'\r'/}")
            if [[ -z "$encryption" || "$encryption" == "none" ]]; then
                raw_file=$(jq -r --argjson idx "$i" '
                    (.configs[$idx] // {}) as $cfg
                    | [
                        ($cfg.variants[]? | select(.key == ($cfg.recommended_variant // "recommended")) | .xray_client_file_v4 // empty),
                        ($cfg.variants[]? | .xray_client_file_v4 // empty)
                      ]
                    | map(select(type == "string" and length > 0))
                    | .[0] // empty
                ' "$json_file" 2> /dev/null || true)
                raw_file=$(trim_ws "${raw_file//$'\r'/}")
                if [[ -n "$raw_file" && -f "$raw_file" ]]; then
                    encryption=$(jq -r '
                        .outbounds[]
                        | select(.tag == "proxy")
                        | .settings.vnext[0].users[0].encryption // empty
                    ' "$raw_file" 2> /dev/null | head -n 1 || true)
                    encryption=$(trim_ws "${encryption//$'\r'/}")
                else
                    encryption=""
                fi
            fi
        fi

        if [[ -z "$encryption" && -n "${keys_encryptions[$i]:-}" ]]; then
            encryption="${keys_encryptions[$i]}"
        fi
        if [[ -z "$encryption" || "$encryption" == "none" ]]; then
            if [[ -n "${existing_encryptions[$i]:-}" && "${existing_encryptions[$i]}" != "none" ]]; then
                encryption="${existing_encryptions[$i]}"
            fi
        fi
        if [[ -z "$encryption" ]]; then
            encryption="none"
        fi
        CONFIG_VLESS_ENCRYPTIONS+=("$encryption")
    done
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
    local seen=" "

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

        [[ " $seen " == *" $uuid "* ]] && continue
        seen="${seen}${uuid} "
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
