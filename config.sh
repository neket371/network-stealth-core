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

CONFIG_DOMAIN_MODULE="$SCRIPT_DIR/modules/config/domain_planner.sh"
if [[ ! -f "$CONFIG_DOMAIN_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_DOMAIN_MODULE="$XRAY_DATA_DIR/modules/config/domain_planner.sh"
fi
if [[ ! -f "$CONFIG_DOMAIN_MODULE" ]]; then
    log ERROR "Не найден модуль доменного планировщика: $CONFIG_DOMAIN_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_DOMAIN_MODULE"

CONFIG_SHARED_HELPERS_MODULE="$SCRIPT_DIR/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    log ERROR "Не найден модуль общих helper-функций config: $CONFIG_SHARED_HELPERS_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_SHARED_HELPERS_MODULE"

CONFIG_ADD_CLIENTS_MODULE="$SCRIPT_DIR/modules/config/add_clients.sh"
if [[ ! -f "$CONFIG_ADD_CLIENTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_ADD_CLIENTS_MODULE="$XRAY_DATA_DIR/modules/config/add_clients.sh"
fi
if [[ ! -f "$CONFIG_ADD_CLIENTS_MODULE" ]]; then
    log ERROR "Не найден модуль add-clients: $CONFIG_ADD_CLIENTS_MODULE"
    exit 1
fi
# shellcheck source=modules/config/add_clients.sh
source "$CONFIG_ADD_CLIENTS_MODULE"

generate_inbound_json() {
    local port="$1"
    local uuid="$2"
    local dest="$3"
    local sni_json="$4" # JSON array of serverNames, or single string for backwards compat
    local privkey="$5"
    local shortid="$6"
    local fp="$7"
    local transport_endpoint="$8"
    local keepalive="$9"
    local grpc_idle="${10}"
    local grpc_health="${11}"
    local transport_mode="${12:-$TRANSPORT}"
    local transport_label="${13:-$transport_endpoint}"
    local decryption_value="${14:-none}"
    local direct_flow="${15:-${XRAY_DIRECT_FLOW:-xtls-rprx-vision}}"

    if ! printf '%s\n' "$sni_json" | jq -e 'type == "array"' > /dev/null 2>&1; then
        sni_json=$(jq -cn --arg sni "$sni_json" '[$sni]')
    fi
    local primary_sni
    primary_sni=$(echo "$sni_json" | jq -r '.[0] // empty' 2> /dev/null || true)
    if [[ -z "$primary_sni" ]]; then
        primary_sni="${dest%%:*}"
    fi

    MSYS2_ARG_CONV_EXCL='*' jq -n \
        --arg port "$port" \
        --arg uuid "$uuid" \
        --arg dest "$dest" \
        --argjson server_names "$sni_json" \
        --arg privkey "$privkey" \
        --arg shortid "$shortid" \
        --arg fp "$fp" \
        --arg endpoint "$transport_endpoint" \
        --arg h2_path "$transport_label" \
        --arg h2_host "$primary_sni" \
        --arg transport "$transport_mode" \
        --arg decryption_value "$decryption_value" \
        --arg direct_flow "$direct_flow" \
        --argjson grpc_idle "$grpc_idle" \
        --argjson grpc_health "$grpc_health" \
        --argjson keepalive "$keepalive" \
        '{
            port: ($port|tonumber),
            listen: "0.0.0.0",
            protocol: "vless",
            settings: {
                clients: [{
                    id: $uuid,
                    flow: $direct_flow
                }],
                decryption: $decryption_value,
                flow: $direct_flow
            },
            streamSettings: (
                {
                    security: "reality",
                    realitySettings: {
                        show: false,
                        dest: $dest,
                        xver: 0,
                        serverNames: $server_names,
                        privateKey: $privkey,
                        shortIds: [$shortid],
                        fingerprint: $fp
                    },
                    sockopt: {
                        tcpFastOpen: true,
                        tcpKeepAliveInterval: $keepalive,
                        tcpCongestion: "bbr"
                    }
                }
                + (if $transport == "xhttp" then
                    {
                        network: "xhttp",
                        xhttpSettings: {
                            path: $endpoint
                        }
                    }
                elif $transport == "http2" then
                    {
                        network: "h2",
                        httpSettings: {
                            path: $h2_path,
                            host: [$h2_host]
                        }
                    }
                else
                    {
                        network: "grpc",
                        grpcSettings: {
                            serviceName: $endpoint,
                            multiMode: true,
                            idle_timeout: $grpc_idle,
                            health_check_timeout: $grpc_health,
                            permit_without_stream: false
                        }
                    }
                end)
            ),
            sniffing: {
                enabled: true,
                destOverride: ["http", "tls", "quic", "fakedns"],
                metadataOnly: false
            }
        }'
}

generate_outbounds_json() {
    jq -n \
        '[
            {
                "protocol": "freedom",
                "tag": "direct",
                "settings": {"domainStrategy": "UseIPv4"},
                "streamSettings": {"sockopt": {"tcpFastOpen": true, "tcpCongestion": "bbr"}}
            },
            {"protocol": "blackhole", "tag": "block"}
        ]'
}

check_xray_version_for_config_generation() {
    if [[ ! -x "$XRAY_BIN" ]]; then
        return 0
    fi

    local version_line version major
    version_line=$("$XRAY_BIN" version 2> /dev/null | head -1 || true)
    version=$(printf '%s\n' "$version_line" | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?' | head -n1 || true)
    if [[ -z "$version" ]]; then
        return 0
    fi

    version="${version#v}"
    major="${version%%.*}"
    if [[ ! "$major" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    if ((major >= 26)); then
        log WARN "Обнаружен Xray ${version}: transport-формат в новых major-версиях может отличаться; при ошибке xray -test зафиксируйте версию через --xray-version."
    fi
}

xray_installed_version() {
    if [[ ! -x "$XRAY_BIN" ]]; then
        return 1
    fi

    local version_line version
    version_line=$("$XRAY_BIN" version 2> /dev/null | head -1 || true)
    version=$(printf '%s\n' "$version_line" | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9._-]+)?' | head -n1 || true)
    [[ -n "$version" ]] || return 1
    printf '%s\n' "${version#v}"
}

ensure_xray_feature_contract() {
    if [[ ! -x "$XRAY_BIN" ]]; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            return 0
        fi
        log ERROR "Xray не найден: ${XRAY_BIN}"
        return 1
    fi

    local version
    version=$(xray_installed_version || true)
    if [[ -n "$version" ]] && version_lt "$version" "${XRAY_CLIENT_MIN_VERSION:-25.9.5}"; then
        log ERROR "Xray ${version} слишком старый для strongest direct stack"
        log ERROR "требуется версия >= ${XRAY_CLIENT_MIN_VERSION:-25.9.5}"
        return 1
    fi

    if ! "$XRAY_BIN" help vlessenc > /dev/null 2>&1; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log WARN "Xray без vlessenc в dry-run режиме; используем test stub"
            return 0
        fi
        log ERROR "Xray не поддерживает subcommand vlessenc"
        return 1
    fi
    return 0
}

build_stub_vless_auth_value() {
    local kind="${1:-client}"
    local random_hex
    random_hex=$(openssl rand -hex 24 2> /dev/null || printf '%048x' "$(rand_between 0 2147483647)")
    printf 'mlkem768x25519plus.native.%s.%s' "$kind" "$random_hex"
}

generate_vless_encryption_pair() {
    local output pq_decryption pq_encryption

    if ! ensure_xray_feature_contract; then
        return 1
    fi

    if [[ "${DRY_RUN:-false}" == "true" || ! -x "$XRAY_BIN" ]]; then
        printf '%s\t%s\n' "$(build_stub_vless_auth_value "600s")" "$(build_stub_vless_auth_value "0rtt")"
        return 0
    fi

    output=$("$XRAY_BIN" vlessenc 2> /dev/null || true)
    pq_decryption=$(printf '%s\n' "$output" | awk '
        /Authentication: ML-KEM-768/ {block=1; next}
        block && /"decryption":/ {print; exit}
    ' | sed -n 's/.*"decryption":[[:space:]]*"\([^"]*\)".*/\1/p')
    pq_encryption=$(printf '%s\n' "$output" | awk '
        /Authentication: ML-KEM-768/ {block=1; next}
        block && /"encryption":/ {print; exit}
    ' | sed -n 's/.*"encryption":[[:space:]]*"\([^"]*\)".*/\1/p')

    if [[ -z "$pq_decryption" || -z "$pq_encryption" ]]; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            printf '%s\t%s\n' "$(build_stub_vless_auth_value "600s")" "$(build_stub_vless_auth_value "0rtt")"
            return 0
        fi
        log ERROR "Не удалось получить ML-KEM-768 пару из xray vlessenc"
        return 1
    fi

    printf '%s\t%s\n' "$pq_decryption" "$pq_encryption"
}

generate_routing_json() {
    echo '{
        "domainStrategy": "AsIs",
        "rules": [
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"},
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}
        ]
    }'
}

setup_mux_settings() {
    if [[ "${TRANSPORT:-xhttp}" == "xhttp" ]]; then
        MUX_ENABLED=false
        MUX_CONCURRENCY=0
        return 0
    fi
    case "$MUX_MODE" in
        on) MUX_ENABLED=true ;;
        off) MUX_ENABLED=false ;;
        auto)
            if [[ "$(rand_between 0 1)" == "1" ]]; then
                MUX_ENABLED=true
            else
                MUX_ENABLED=false
            fi
            ;;
        *) MUX_ENABLED=true ;;
    esac
    if [[ "$MUX_ENABLED" == true ]]; then
        MUX_CONCURRENCY=$(rand_between "$MUX_CONCURRENCY_MIN" "$MUX_CONCURRENCY_MAX")
    else
        MUX_CONCURRENCY=0
    fi
}

build_config() {
    log STEP "Собираем конфигурацию Xray (modular)..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Конфигурация не пересоздаётся (используем текущую)"
        return 0
    fi

    local inbounds='[]'
    # shellcheck disable=SC2034 # Used via nameref in pick_random_from_array.
    local -a fp_pool=("chrome" "chrome" "chrome" "firefox" "chrome" "firefox")

    CONFIG_DOMAINS=()
    CONFIG_SNIS=()
    CONFIG_TRANSPORT_ENDPOINTS=()
    CONFIG_DESTS=()
    CONFIG_FPS=()
    CONFIG_PROVIDER_FAMILIES=()
    CONFIG_VLESS_ENCRYPTIONS=()
    CONFIG_VLESS_DECRYPTIONS=()

    setup_mux_settings
    check_xray_version_for_config_generation
    ensure_xray_feature_contract

    if [[ ${#PORTS[@]} -lt $NUM_CONFIGS ]]; then
        log ERROR "Массив портов (${#PORTS[@]}) меньше NUM_CONFIGS ($NUM_CONFIGS)"
        exit 1
    fi
    if [[ ${#UUIDS[@]} -lt $NUM_CONFIGS || ${#PRIVATE_KEYS[@]} -lt $NUM_CONFIGS || ${#SHORT_IDS[@]} -lt $NUM_CONFIGS ]]; then
        log ERROR "Массивы ключей не соответствуют NUM_CONFIGS ($NUM_CONFIGS)"
        exit 1
    fi

    if ! build_domain_plan "$NUM_CONFIGS" "true"; then
        log ERROR "Не удалось сформировать доменный план для конфигурации"
        exit 1
    fi

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${DOMAIN_SELECTION_PLAN[$i]:-${AVAILABLE_DOMAINS[0]}}"

        build_inbound_profile_for_domain "$domain" fp_pool
        CONFIG_DOMAINS+=("$domain")
        CONFIG_SNIS+=("$PROFILE_SNI")
        CONFIG_TRANSPORT_ENDPOINTS+=("$PROFILE_TRANSPORT_ENDPOINT")
        CONFIG_DESTS+=("$PROFILE_DEST")
        CONFIG_FPS+=("$PROFILE_FP")
        CONFIG_PROVIDER_FAMILIES+=("$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")")

        local vless_pair vless_decryption vless_encryption
        vless_pair=$(generate_vless_encryption_pair) || exit 1
        IFS=$'\t' read -r vless_decryption vless_encryption <<< "$vless_pair"
        CONFIG_VLESS_DECRYPTIONS+=("$vless_decryption")
        CONFIG_VLESS_ENCRYPTIONS+=("$vless_encryption")

        local sni_count
        sni_count=$(echo "$PROFILE_SNI_JSON" | jq 'length' 2> /dev/null || echo 1)
        log INFO "Config $((i + 1)): ${domain} -> ${PROFILE_DEST} (${PROFILE_FP}, ${TRANSPORT}, SNIs: ${sni_count})"

        local inbound_v4
        inbound_v4=$(generate_profile_inbound_json \
            "${PORTS[$i]}" "${UUIDS[$i]}" "${PRIVATE_KEYS[$i]}" "${SHORT_IDS[$i]}" "${CONFIG_VLESS_DECRYPTIONS[$i]}")

        inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v4" '. + [$ib]')

        if [[ "$HAS_IPV6" == true ]]; then
            if [[ -z "${PORTS_V6[$i]:-}" ]]; then
                log ERROR "HAS_IPV6=true, но IPv6 порт для конфига #$((i + 1)) не задан"
                exit 1
            fi
            local inbound_v6
            if ! inbound_v6=$(echo "$inbound_v4" | jq --arg port "${PORTS_V6[$i]}" '.listen = "::" | .port = ($port|tonumber)' 2> /dev/null); then
                log ERROR "Ошибка генерации IPv6 inbound для конфига #$((i + 1)) (port=${PORTS_V6[$i]})"
                exit 1
            fi
            inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v6" '. + [$ib]')
        fi

        progress_bar $((i + 1)) "$NUM_CONFIGS"
    done

    local outbounds
    outbounds=$(generate_outbounds_json)
    local routing
    routing=$(generate_routing_json)

    backup_file "$XRAY_CONFIG"
    local tmp_config
    tmp_config=$(create_temp_xray_config_file)
    jq -n \
        --argjson inbounds "$inbounds" \
        --argjson outbounds "$outbounds" \
        --argjson routing "$routing" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        '{
            log: {
                loglevel: "warning",
                access: "/var/log/xray/access.log",
                error: "/var/log/xray/error.log"
            },
            dns: {
                servers: [
                    "https+local://1.1.1.1/dns-query",
                    "https+local://8.8.8.8/dns-query",
                    "localhost"
                ],
                queryStrategy: "UseIPv4"
            },
            version: {
                min: $min_version
            },
            inbounds: $inbounds,
            outbounds: $outbounds,
            routing: $routing,
            policy: {
                levels: {
                    "0": {
                        handshake: 4,
                        connIdle: 600,
                        uplinkOnly: 2,
                        downlinkOnly: 5,
                        bufferSize: 1024
                    }
                },
                system: {
                    statsInboundUplink: false,
                    statsInboundDownlink: false
                }
            }
        }' > "$tmp_config"

    set_temp_xray_config_permissions "$tmp_config"

    if ! apply_validated_config "$tmp_config"; then
        exit 1
    fi

    log OK "Конфигурация создана"
}

rebuild_config_for_transport() {
    local target_transport="${1:-xhttp}"
    local inbounds='[]'
    local -a next_domains=()
    local -a next_snis=()
    local -a next_endpoints=()
    local -a next_dests=()
    local -a next_fps=()
    local -a next_provider_families=()
    local -a next_vless_encryptions=()
    local -a next_vless_decryptions=()
    local i

    if ((NUM_CONFIGS < 1)); then
        log ERROR "Нет конфигураций для rebuild transport"
        return 1
    fi

    check_xray_version_for_config_generation
    ensure_xray_feature_contract
    local previous_transport="${TRANSPORT:-xhttp}"
    TRANSPORT="$target_transport"
    setup_mux_settings

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${CONFIG_DOMAINS[$i]:-}"
        local sni="${CONFIG_SNIS[$i]:-$domain}"
        local fp="${CONFIG_FPS[$i]:-chrome}"
        local dest="${CONFIG_DESTS[$i]:-}"
        local transport_endpoint
        transport_endpoint="${CONFIG_TRANSPORT_ENDPOINTS[$i]:-}"
        local provider_family="${CONFIG_PROVIDER_FAMILIES[$i]:-}"
        local vless_encryption="${CONFIG_VLESS_ENCRYPTIONS[$i]:-}"
        local vless_decryption="${CONFIG_VLESS_DECRYPTIONS[$i]:-}"

        [[ -n "$domain" ]] || {
            log ERROR "Не найден домен для конфига #$((i + 1))"
            TRANSPORT="$previous_transport"
            return 1
        }
        [[ -n "$dest" ]] || dest="${domain}:$(detect_reality_dest "$domain")"
        [[ -n "$sni" ]] || sni="$domain"
        [[ -n "$provider_family" ]] || provider_family="$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")"
        if [[ -z "$transport_endpoint" || "$target_transport" == "xhttp" ]]; then
            if [[ "$target_transport" == "xhttp" ]]; then
                transport_endpoint=$(generate_xhttp_path_for_domain "$domain")
            else
                transport_endpoint=$(select_grpc_service_name "$domain")
            fi
        fi

        local payload="$transport_endpoint"
        if [[ "$target_transport" == "http2" ]]; then
            payload=$(grpc_service_to_http2_path "$transport_endpoint")
        fi

        local sni_json
        sni_json=$(jq -cn --arg sni "$sni" '[$sni]')
        local keepalive grpc_idle grpc_health
        keepalive=$(rand_between "$TCP_KEEPALIVE_MIN" "$TCP_KEEPALIVE_MAX")
        grpc_idle=$(rand_between "$GRPC_IDLE_TIMEOUT_MIN" "$GRPC_IDLE_TIMEOUT_MAX")
        grpc_health=$(rand_between "$GRPC_HEALTH_TIMEOUT_MIN" "$GRPC_HEALTH_TIMEOUT_MAX")

        if [[ "$target_transport" == "xhttp" ]]; then
            if [[ -z "$vless_decryption" || "$vless_decryption" == "none" || -z "$vless_encryption" || "$vless_encryption" == "none" ]]; then
                local vless_pair
                vless_pair=$(generate_vless_encryption_pair) || {
                    TRANSPORT="$previous_transport"
                    return 1
                }
                IFS=$'\t' read -r vless_decryption vless_encryption <<< "$vless_pair"
            fi
        else
            vless_decryption="none"
            vless_encryption="none"
        fi

        local inbound_v4
        inbound_v4=$(generate_inbound_json \
            "${PORTS[$i]}" "${UUIDS[$i]}" "$dest" "$sni_json" "${PRIVATE_KEYS[$i]}" "${SHORT_IDS[$i]}" \
            "$fp" "$transport_endpoint" "$keepalive" "$grpc_idle" "$grpc_health" \
            "$target_transport" "$payload" "$vless_decryption" "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}")
        inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v4" '. + [$ib]')

        if [[ "$HAS_IPV6" == true && -n "${PORTS_V6[$i]:-}" ]]; then
            local inbound_v6
            inbound_v6=$(echo "$inbound_v4" | jq --arg port "${PORTS_V6[$i]}" '.listen = "::" | .port = ($port|tonumber)')
            inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v6" '. + [$ib]')
        fi

        next_domains+=("$domain")
        next_snis+=("$sni")
        next_endpoints+=("$transport_endpoint")
        next_dests+=("$dest")
        next_fps+=("$fp")
        next_provider_families+=("$provider_family")
        next_vless_encryptions+=("$vless_encryption")
        next_vless_decryptions+=("$vless_decryption")
    done

    local outbounds routing tmp_config
    outbounds=$(generate_outbounds_json)
    routing=$(generate_routing_json)
    backup_file "$XRAY_CONFIG"
    tmp_config=$(create_temp_xray_config_file)
    jq -n \
        --argjson inbounds "$inbounds" \
        --argjson outbounds "$outbounds" \
        --argjson routing "$routing" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        '{
            log: {
                loglevel: "warning",
                access: "/var/log/xray/access.log",
                error: "/var/log/xray/error.log"
            },
            dns: {
                servers: [
                    "https+local://1.1.1.1/dns-query",
                    "https+local://8.8.8.8/dns-query",
                    "localhost"
                ],
                queryStrategy: "UseIPv4"
            },
            version: {
                min: $min_version
            },
            inbounds: $inbounds,
            outbounds: $outbounds,
            routing: $routing,
            policy: {
                levels: {
                    "0": {
                        handshake: 4,
                        connIdle: 600,
                        uplinkOnly: 2,
                        downlinkOnly: 5,
                        bufferSize: 1024
                    }
                },
                system: {
                    statsInboundUplink: false,
                    statsInboundDownlink: false
                }
            }
        }' > "$tmp_config"
    set_temp_xray_config_permissions "$tmp_config"
    if ! apply_validated_config "$tmp_config"; then
        TRANSPORT="$previous_transport"
        return 1
    fi

    CONFIG_DOMAINS=("${next_domains[@]}")
    CONFIG_SNIS=("${next_snis[@]}")
    CONFIG_TRANSPORT_ENDPOINTS=("${next_endpoints[@]}")
    CONFIG_DESTS=("${next_dests[@]}")
    CONFIG_FPS=("${next_fps[@]}")
    CONFIG_PROVIDER_FAMILIES=("${next_provider_families[@]}")
    CONFIG_VLESS_ENCRYPTIONS=("${next_vless_encryptions[@]}")
    CONFIG_VLESS_DECRYPTIONS=("${next_vless_decryptions[@]}")
    TRANSPORT="$target_transport"
    return 0
}

xray_test_config_as_service_user() {
    local file="$1"

    if command -v runuser > /dev/null 2>&1; then
        if runuser -u "$XRAY_USER" -- "$XRAY_BIN" -test -c "$file"; then
            return 0
        fi
    fi

    if command -v sudo > /dev/null 2>&1; then
        if sudo -n -u "$XRAY_USER" -- "$XRAY_BIN" -test -c "$file"; then
            return 0
        fi
    fi

    # shellcheck disable=SC2016 # Intentional: $0/$1 expand at runtime inside su -c
    if su -s /bin/sh "$XRAY_USER" -c '"$0" -test -c "$1"' "$XRAY_BIN" "$file"; then
        return 0
    fi

    "$XRAY_BIN" -test -c "$file"
}

xray_config_test() {
    xray_test_config_as_service_user "$XRAY_CONFIG"
}

xray_config_test_file() {
    local file="$1"
    xray_test_config_as_service_user "$file"
}

xray_config_test_ok() {
    local file="${1:-$XRAY_CONFIG}"
    local test_output=""

    if ! test_output=$(xray_config_test_file "$file" 2>&1); then
        [[ -n "$test_output" ]] && printf '%s\n' "$test_output"
        return 1
    fi
    if [[ "$test_output" != *"Configuration OK"* ]]; then
        debug_file "xray -test succeeded without explicit 'Configuration OK' marker"
    fi
    return 0
}

set_temp_xray_config_permissions() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    chmod 640 "$file"
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        chown "root:${XRAY_GROUP}" "$file" 2> /dev/null || true
    else
        chown root:root "$file" 2> /dev/null || true
        chmod 600 "$file" 2> /dev/null || true
    fi
}

create_temp_xray_config_file() {
    local tmp_base="${TMPDIR:-/tmp}"
    if [[ ! -d "$tmp_base" || ! -w "$tmp_base" ]]; then
        tmp_base="/tmp"
    fi

    local _old_umask
    local tmp_config
    _old_umask=$(umask)
    umask 077
    if ! tmp_config=$(mktemp "${tmp_base}/xray-config.XXXXXX.json"); then
        umask "$_old_umask"
        return 1
    fi
    umask "$_old_umask"
    printf '%s\n' "$tmp_config"
}

apply_validated_config() {
    local candidate_file="$1"
    if ! xray_config_test_ok "$candidate_file"; then
        log ERROR "Xray отклонил новую конфигурацию"
        rm -f "$candidate_file"
        return 1
    fi
    mv "$candidate_file" "$XRAY_CONFIG"
    chown "root:${XRAY_GROUP}" "$XRAY_CONFIG"
    chmod 640 "$XRAY_CONFIG"
    return 0
}

save_environment() {
    log STEP "Сохраняем окружение..."

    local installed_version install_date
    installed_version=$("$XRAY_BIN" version 2> /dev/null | head -1 | awk '{print $2}' || true)
    install_date=$(date '+%Y-%m-%d %H:%M:%S')

    backup_file "$XRAY_ENV"
    {
        printf '# Network Stealth Core %s Configuration\n' "$SCRIPT_VERSION"
        write_env_kv DOMAIN_PROFILE "${DOMAIN_PROFILE:-$DOMAIN_TIER}"
        write_env_kv XRAY_DOMAIN_PROFILE "${DOMAIN_PROFILE:-$DOMAIN_TIER}"
        write_env_kv DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv XRAY_DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv MUX_MODE "$MUX_MODE"
        write_env_kv TRANSPORT "$TRANSPORT"
        write_env_kv XRAY_TRANSPORT "$TRANSPORT"
        write_env_kv ADVANCED_MODE "$ADVANCED_MODE"
        write_env_kv XRAY_ADVANCED "$ADVANCED_MODE"
        write_env_kv PROGRESS_MODE "$PROGRESS_MODE"
        write_env_kv XRAY_PROGRESS_MODE "$PROGRESS_MODE"
        write_env_kv MUX_ENABLED "$MUX_ENABLED"
        write_env_kv MUX_CONCURRENCY "$MUX_CONCURRENCY"
        write_env_kv SHORT_ID_BYTES_MIN "$SHORT_ID_BYTES_MIN"
        write_env_kv SHORT_ID_BYTES_MAX "$SHORT_ID_BYTES_MAX"
        write_env_kv DOMAIN_CHECK "$DOMAIN_CHECK"
        write_env_kv DOMAIN_CHECK_TIMEOUT "$DOMAIN_CHECK_TIMEOUT"
        write_env_kv DOMAIN_CHECK_PARALLELISM "$DOMAIN_CHECK_PARALLELISM"
        write_env_kv REALITY_TEST_PORTS "$REALITY_TEST_PORTS"
        write_env_kv SKIP_REALITY_CHECK "$SKIP_REALITY_CHECK"
        write_env_kv DOMAIN_HEALTH_FILE "$DOMAIN_HEALTH_FILE"
        write_env_kv DOMAIN_HEALTH_PROBE_TIMEOUT "$DOMAIN_HEALTH_PROBE_TIMEOUT"
        write_env_kv DOMAIN_HEALTH_RATE_LIMIT_MS "$DOMAIN_HEALTH_RATE_LIMIT_MS"
        write_env_kv DOMAIN_HEALTH_MAX_PROBES "$DOMAIN_HEALTH_MAX_PROBES"
        write_env_kv DOMAIN_HEALTH_RANKING "$DOMAIN_HEALTH_RANKING"
        write_env_kv HEALTH_CHECK_INTERVAL "$HEALTH_CHECK_INTERVAL"
        write_env_kv SELF_CHECK_ENABLED "$SELF_CHECK_ENABLED"
        write_env_kv SELF_CHECK_URLS "$SELF_CHECK_URLS"
        write_env_kv SELF_CHECK_TIMEOUT_SEC "$SELF_CHECK_TIMEOUT_SEC"
        write_env_kv SELF_CHECK_STATE_FILE "$SELF_CHECK_STATE_FILE"
        write_env_kv SELF_CHECK_HISTORY_FILE "$SELF_CHECK_HISTORY_FILE"
        write_env_kv LOG_RETENTION_DAYS "$LOG_RETENTION_DAYS"
        write_env_kv LOG_MAX_SIZE_MB "$LOG_MAX_SIZE_MB"
        write_env_kv HEALTH_LOG "$HEALTH_LOG"
        write_env_kv XRAY_POLICY "$XRAY_POLICY"
        write_env_kv XRAY_DOMAIN_CATALOG_FILE "$XRAY_DOMAIN_CATALOG_FILE"
        write_env_kv MEASUREMENTS_DIR "$MEASUREMENTS_DIR"
        write_env_kv MEASUREMENTS_SUMMARY_FILE "$MEASUREMENTS_SUMMARY_FILE"
        write_env_kv DOMAIN_QUARANTINE_FAIL_STREAK "$DOMAIN_QUARANTINE_FAIL_STREAK"
        write_env_kv DOMAIN_QUARANTINE_COOLDOWN_MIN "$DOMAIN_QUARANTINE_COOLDOWN_MIN"
        write_env_kv PRIMARY_DOMAIN_MODE "$PRIMARY_DOMAIN_MODE"
        write_env_kv PRIMARY_PIN_DOMAIN "$PRIMARY_PIN_DOMAIN"
        write_env_kv PRIMARY_ADAPTIVE_TOP_N "$PRIMARY_ADAPTIVE_TOP_N"
        write_env_kv DOWNLOAD_HOST_ALLOWLIST "$DOWNLOAD_HOST_ALLOWLIST"
        write_env_kv GH_PROXY_BASE "$GH_PROXY_BASE"
        write_env_kv KEEP_LOCAL_BACKUPS "$KEEP_LOCAL_BACKUPS"
        write_env_kv REUSE_EXISTING "$REUSE_EXISTING"
        write_env_kv AUTO_ROLLBACK "$AUTO_ROLLBACK"
        write_env_kv XRAY_VERSION "$XRAY_VERSION"
        write_env_kv XRAY_MIRRORS "$XRAY_MIRRORS"
        write_env_kv MINISIGN_MIRRORS "$MINISIGN_MIRRORS"
        write_env_kv XRAY_GEO_DIR "$XRAY_GEO_DIR"
        write_env_kv QR_ENABLED "$QR_ENABLED"
        write_env_kv XRAY_CLIENT_MIN_VERSION "$XRAY_CLIENT_MIN_VERSION"
        write_env_kv XRAY_DIRECT_FLOW "$XRAY_DIRECT_FLOW"
        write_env_kv STEALTH_CONTRACT_VERSION "$STEALTH_CONTRACT_VERSION"
        write_env_kv BROWSER_DIALER_ENV_NAME "$BROWSER_DIALER_ENV_NAME"
        write_env_kv XRAY_BROWSER_DIALER_ADDRESS "$XRAY_BROWSER_DIALER_ADDRESS"
        write_env_kv REPLAN "$REPLAN"
        write_env_kv AUTO_UPDATE "$AUTO_UPDATE"
        write_env_kv AUTO_UPDATE_ONCALENDAR "$AUTO_UPDATE_ONCALENDAR"
        write_env_kv AUTO_UPDATE_RANDOM_DELAY "$AUTO_UPDATE_RANDOM_DELAY"
        write_env_kv ALLOW_INSECURE_SHA256 "$ALLOW_INSECURE_SHA256"
        write_env_kv ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP "$ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP"
        write_env_kv REQUIRE_MINISIGN "$REQUIRE_MINISIGN"
        write_env_kv ALLOW_NO_SYSTEMD "$ALLOW_NO_SYSTEMD"
        write_env_kv GEO_VERIFY_HASH "$GEO_VERIFY_HASH"
        write_env_kv GEO_VERIFY_STRICT "$GEO_VERIFY_STRICT"
        write_env_kv XRAY_SCRIPT_PATH "$XRAY_SCRIPT_PATH"
        write_env_kv XRAY_UPDATE_SCRIPT "$XRAY_UPDATE_SCRIPT"
        write_env_kv NUM_CONFIGS "$NUM_CONFIGS"
        write_env_kv XRAY_NUM_CONFIGS "$NUM_CONFIGS"
        write_env_kv SPIDER_MODE "${SPIDER_MODE:-false}"
        write_env_kv XRAY_SPIDER_MODE "$SPIDER_MODE"
        write_env_kv START_PORT "$START_PORT"
        write_env_kv XRAY_START_PORT "$START_PORT"
        write_env_kv INSTALLED_VERSION "$installed_version"
        write_env_kv INSTALL_DATE "$install_date"
        write_env_kv SERVER_IP "$SERVER_IP"
        write_env_kv SERVER_IP6 "$SERVER_IP6"
    } | atomic_write "$XRAY_ENV" 0600

    log OK "Окружение сохранено в $XRAY_ENV"
}

BOX60_TOP=""
BOX60_SEP=""
BOX60_BOT=""
BOX60_WIDTH=60

box60_init() {
    ui_init_glyphs
    BOX60_TOP="$(ui_box_border_string top "$BOX60_WIDTH")"
    BOX60_SEP="$(ui_box_line_string "$(ui_repeat_char "$UI_BOX_H" "$BOX60_WIDTH")" "$BOX60_WIDTH")"
    BOX60_BOT="$(ui_box_border_string bottom "$BOX60_WIDTH")"
}

box60_line() {
    local text="$1"
    box60_init
    printf '%s\n' "$(ui_box_line_string "$text" "$BOX60_WIDTH")"
}

client_variant_catalog() {
    local transport="${1:-${TRANSPORT:-xhttp}}"
    case "${transport,,}" in
        xhttp)
            printf '%s\n' "recommended	auto"
            printf '%s\n' "rescue	packet-up"
            printf '%s\n' "emergency	stream-up"
            ;;
        *)
            printf '%s\n' "standard	"
            ;;
    esac
}

client_variant_title() {
    local key="${1:-standard}"
    case "$key" in
        recommended) printf '%s' "recommended" ;;
        rescue) printf '%s' "rescue" ;;
        emergency) printf '%s' "emergency" ;;
        *) printf '%s' "standard" ;;
    esac
}

client_variant_category() {
    local key="${1:-standard}"
    case "$key" in
        recommended) printf '%s' "direct" ;;
        rescue) printf '%s' "fallback" ;;
        emergency) printf '%s' "emergency" ;;
        *) printf '%s' "legacy" ;;
    esac
}

client_variant_note() {
    local key="${1:-standard}"
    case "$key" in
        recommended) printf '%s' "primary strongest direct profile" ;;
        rescue) printf '%s' "packet-up fallback for difficult networks" ;;
        emergency) printf '%s' "field-only emergency profile; requires browser dialer and raw xray json import" ;;
        *) printf '%s' "legacy-compatible profile" ;;
    esac
}

client_variant_requires_browser_dialer() {
    local key="${1:-standard}"
    [[ "$key" == "emergency" ]] && printf '%s' "true" || printf '%s' "false"
}

client_variant_generates_link() {
    local key="${1:-standard}"
    [[ "$key" == "emergency" ]] && printf '%s' "false" || printf '%s' "true"
}

client_variant_link_suffix() {
    local key="${1:-standard}"
    local suffix="${2:-}"
    if [[ -n "$suffix" ]]; then
        printf '%s' "${key}-${suffix}"
    else
        printf '%s' "$key"
    fi
}

build_client_vless_link() {
    local server="$1"
    local port="$2"
    local uuid="$3"
    local sni="$4"
    local fp="$5"
    local public_key="$6"
    local short_id="$7"
    local transport="$8"
    local endpoint="$9"
    local mode="${10:-}"
    local label="${11:-config}"
    local params
    params=$(build_vless_query_params "$sni" "$fp" "$public_key" "$short_id" "$transport" "$endpoint" "$mode")
    printf 'vless://%s@%s:%s?%s#%s' "$uuid" "$server" "$port" "$params" "$label"
}

variant_xray_relative_path() {
    local config_index="$1"
    local variant_key="$2"
    local ip_family="$3"
    printf 'raw-xray/config-%s-%s-%s.json' "$config_index" "$variant_key" "$ip_family"
}

build_xray_client_variant_json() {
    local server="$1"
    local port="$2"
    local uuid="$3"
    local sni="$4"
    local fp="$5"
    local public_key="$6"
    local short_id="$7"
    local transport="$8"
    local endpoint="$9"
    local mode="${10:-}"
    local vless_encryption="${11:-none}"
    local requires_browser_dialer="${12:-false}"
    local direct_flow="${13:-${XRAY_DIRECT_FLOW:-xtls-rprx-vision}}"

    local transport_json='{}'
    case "${transport,,}" in
        xhttp)
            transport_json=$(jq -n --arg path "$endpoint" --arg variant_mode "${mode:-auto}" '{
                network: "xhttp",
                xhttpSettings: {
                    path: $path,
                    mode: $variant_mode
                }
            }')
            ;;
        http2)
            transport_json=$(jq -n --arg path "$endpoint" --arg host "$sni" '{
                network: "h2",
                httpSettings: {
                    path: $path,
                    host: [$host]
                }
            }')
            ;;
        *)
            transport_json=$(jq -n --arg service "$endpoint" '{
                network: "grpc",
                grpcSettings: {
                    serviceName: $service,
                    multiMode: true
                }
            }')
            ;;
    esac

    jq -n \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg sni "$sni" \
        --arg fp "$fp" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        --arg vless_encryption "$vless_encryption" \
        --arg direct_flow "$direct_flow" \
        --arg requires_browser_dialer "$requires_browser_dialer" \
        --argjson transport_obj "$transport_json" \
        '{
            version: { min: $min_version },
            log: {loglevel: "warning"},
            inbounds: [
                {
                    tag: "socks",
                    listen: "127.0.0.1",
                    port: 10808,
                    protocol: "socks",
                    settings: {
                        udp: true
                    }
                }
            ],
            outbounds: [
                (
                    {
                        tag: "proxy",
                        protocol: "vless",
                        settings: {
                            vnext: [
                                {
                                    address: $server,
                                    port: $port,
                                    users: [
                                        {
                                            id: $uuid,
                                            encryption: $vless_encryption,
                                            flow: $direct_flow
                                        }
                                    ]
                                }
                            ]
                        },
                        streamSettings: (
                            {
                                security: "reality",
                                realitySettings: {
                                    serverName: $sni,
                                    fingerprint: $fp,
                                    publicKey: $public_key,
                                    shortId: $short_id
                                }
                            } + $transport_obj
                        )
                    }
                ),
                {tag: "direct", protocol: "freedom"},
                {tag: "block", protocol: "blackhole"}
            ],
            routing: {
                domainStrategy: "AsIs"
            }
        }'
}

render_clients_txt_from_json() {
    local json_file="$1"
    local client_file="$2"
    local links_file="${XRAY_KEYS}/clients-links.txt"
    local rule58
    rule58="$(ui_rule_string 58)"
    box60_init

    if ! jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
        log ERROR "Некорректный JSON-источник для clients.txt: ${json_file}"
        return 1
    fi

    local server_ipv4 server_ipv6 generated transport_raw spider_mode
    server_ipv4=$(jq -r '.server_ipv4 // empty' "$json_file" 2> /dev/null || true)
    server_ipv6=$(jq -r '.server_ipv6 // empty' "$json_file" 2> /dev/null || true)
    generated=$(jq -r '.generated // empty' "$json_file" 2> /dev/null || true)
    transport_raw=$(jq -r '.transport // "xhttp"' "$json_file" 2> /dev/null || echo "xhttp")
    spider_mode=$(jq -r '.spider_mode // false' "$json_file" 2> /dev/null || echo "false")

    [[ -n "$server_ipv4" ]] || server_ipv4="${SERVER_IP:-unknown}"
    [[ -n "$server_ipv6" ]] || server_ipv6="N/A"
    generated=$(printf '%s' "$generated" | tr -s '[:space:]' ' ')
    generated=$(trim_ws "$generated")
    [[ -n "$generated" ]] || generated="$(format_generated_timestamp)"

    local transport_summary
    transport_summary=$(transport_display_name "$transport_raw")

    local mux_summary="Disabled"
    if [[ "${transport_raw,,}" == "xhttp" ]]; then
        mux_summary="Disabled (xhttp handles transport mixing itself)"
    elif [[ "${MUX_ENABLED:-false}" == true ]]; then
        mux_summary="Enabled (Concurrency: ${MUX_CONCURRENCY})"
    fi

    backup_file "$client_file"
    local tmp_client
    tmp_client=$(mktemp "${client_file}.tmp.XXXXXX")

    local header_title="Network Stealth Core ${SCRIPT_VERSION} - CLIENT CONFIGS"
    local header_width
    header_width=$(ui_box_width_for_lines 60 90 "$header_title")

    {
        printf '%s\n' "$(ui_box_border_string top "$header_width")"
        printf '%s\n' "$(ui_box_line_string "$header_title" "$header_width")"
        printf '%s\n' "$(ui_box_border_string bottom "$header_width")"
        echo ""
    } > "$tmp_client"

    cat >> "$tmp_client" << EOF
Server: ${server_ipv4}
Server IPv6: ${server_ipv6}
Generated: ${generated}
Transport: ${transport_summary}
Security: Reality + xhttp + VLESS encryption + ${XRAY_DIRECT_FLOW:-xtls-rprx-vision}
DPI Bypass: strongest direct stack + emergency browser-assisted fallback
Spider Mode: $([[ "${spider_mode}" == "true" ]] && echo "Enabled" || echo "Disabled")
Install UX: $([[ "${ADVANCED_MODE:-false}" == "true" ]] && echo "advanced" || echo "minimal")
Quick import links: ${links_file}

${rule58}

recommended clients:

- android: v2rayNG 1.8+, nekoray, hiddify
- ios: shadowrocket, streisand, foxray
- windows: v2rayn 6+, nekoray, invisible man
- macos: v2rayu, qv2ray, foxray
- linux: xray-core, nekoray

${rule58}

⚙️  РЕКОМЕНДУЕМЫЕ НАСТРОЙКИ КЛИЕНТА:

✓ Mux: ${mux_summary}
✓ TCP Fast Open: ON
✓ Domain Strategy: AsIs
✓ Sniffing: Enabled
✓ Transport default: xhttp auto
✓ Fallback: xhttp packet-up
✓ Emergency: xhttp stream-up + browser dialer (raw xray only)

${rule58}

🔗 КОНФИГУРАЦИИ:

EOF

    local config_count
    config_count=$(jq -r '.configs | length' "$json_file" 2> /dev/null || echo 0)

    local i
    for ((i = 0; i < config_count; i++)); do
        local domain sni fp transport_value endpoint port_v4 port_v6 provider_family flow_value encryption_value
        domain=$(jq -r ".configs[$i].domain // \"unknown\"" "$json_file" 2> /dev/null || echo "unknown")
        sni=$(jq -r ".configs[$i].sni // .configs[$i].domain // \"unknown\"" "$json_file" 2> /dev/null || echo "unknown")
        fp=$(jq -r ".configs[$i].fingerprint // \"chrome\"" "$json_file" 2> /dev/null || echo "chrome")
        transport_value=$(jq -r ".configs[$i].transport // \"xhttp\"" "$json_file" 2> /dev/null || echo "xhttp")
        endpoint=$(jq -r ".configs[$i].transport_endpoint // .configs[$i].grpc_service // \"-\"" "$json_file" 2> /dev/null || echo "-")
        port_v4=$(jq -r ".configs[$i].port_ipv4 // \"N/A\"" "$json_file" 2> /dev/null || echo "N/A")
        port_v6=$(jq -r ".configs[$i].port_ipv6 // empty | tostring" "$json_file" 2> /dev/null || true)
        provider_family=$(jq -r ".configs[$i].provider_family // \"-\"" "$json_file" 2> /dev/null || echo "-")
        flow_value=$(jq -r ".configs[$i].flow // \"${XRAY_DIRECT_FLOW:-xtls-rprx-vision}\"" "$json_file" 2> /dev/null || echo "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}")
        encryption_value=$(jq -r ".configs[$i].vless_encryption // \"none\"" "$json_file" 2> /dev/null || echo "none")

        [[ -n "$port_v6" && "$port_v6" != "null" ]] || port_v6="N/A"

        local priority=""
        if [[ $i -eq 0 ]]; then
            priority=" * ГЛАВНЫЙ"
        elif [[ $i -eq 1 ]]; then
            priority=" ~ РЕЗЕРВНЫЙ"
        fi

        local transport_display transport_extra_key
        transport_display=$(transport_display_name "$transport_value")
        transport_extra_key=$(transport_endpoint_label "$transport_value")

        {
            echo "$BOX60_TOP"
            box60_line "Config $((i + 1)): ${domain}${priority}"
            echo "$BOX60_SEP"
            box60_line "Port IPv4: ${port_v4}"
            box60_line "Port IPv6: ${port_v6}"
            box60_line "SNI: ${sni}"
            box60_line "Provider: ${provider_family}"
            box60_line "Fingerprint: ${fp}"
            box60_line "Transport: ${transport_display}"
            box60_line "${transport_extra_key}: ${endpoint}"
            box60_line "Flow: ${flow_value}"
            box60_line "VLESS enc: ${encryption_value}"
            echo "$BOX60_BOT"
            echo ""
            echo "quick vless links: ${links_file}"
            echo ""
        } >> "$tmp_client"

        local variant_count
        variant_count=$(jq -r ".configs[$i].variants | length" "$json_file" 2> /dev/null || echo 0)
        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local j
        for ((j = 0; j < variant_count; j++)); do
            local variant_key variant_note variant_mode vless_v4 vless_v6 raw_v4 raw_v6 import_hint variant_category requires_browser_dialer
            variant_key=$(jq -r ".configs[$i].variants[$j].key // .configs[$i].recommended_variant // \"standard\"" "$json_file" 2> /dev/null || echo "standard")
            variant_note=$(jq -r ".configs[$i].variants[$j].note // empty" "$json_file" 2> /dev/null || true)
            variant_mode=$(jq -r ".configs[$i].variants[$j].mode // empty" "$json_file" 2> /dev/null || true)
            vless_v4=$(jq -r ".configs[$i].variants[$j].vless_v4 // .configs[$i].vless_v4 // empty" "$json_file" 2> /dev/null || true)
            vless_v6=$(jq -r ".configs[$i].variants[$j].vless_v6 // .configs[$i].vless_v6 // empty" "$json_file" 2> /dev/null || true)
            raw_v4=$(jq -r ".configs[$i].variants[$j].xray_client_file_v4 // empty" "$json_file" 2> /dev/null || true)
            raw_v6=$(jq -r ".configs[$i].variants[$j].xray_client_file_v6 // empty" "$json_file" 2> /dev/null || true)
            import_hint=$(jq -r ".configs[$i].variants[$j].import_hint // empty" "$json_file" 2> /dev/null || true)
            variant_category=$(jq -r ".configs[$i].variants[$j].category // empty" "$json_file" 2> /dev/null || true)
            requires_browser_dialer=$(jq -r ".configs[$i].variants[$j].requires.browser_dialer // false" "$json_file" 2> /dev/null || echo "false")
            [[ -n "$variant_note" && "$variant_note" != "null" ]] || variant_note=$(client_variant_note "$variant_key")
            [[ -n "$import_hint" && "$import_hint" != "null" ]] || import_hint=$(client_variant_import_hint "$variant_key")

            {
                echo "variant: $(client_variant_title "$variant_key")"
                if [[ -n "$variant_category" && "$variant_category" != "null" ]]; then
                    echo "category: ${variant_category}"
                fi
                if [[ -n "$variant_mode" && "$variant_mode" != "null" ]]; then
                    echo "mode: ${variant_mode}"
                fi
                echo "note: ${variant_note}"
                echo "import hint: ${import_hint}"
                if [[ "$requires_browser_dialer" == "true" ]]; then
                    echo "requires: browser dialer via env ${BROWSER_DIALER_ENV_NAME:-xray.browser.dialer}"
                fi
                if [[ -n "$vless_v4" && "$vless_v4" != "null" ]]; then
                    echo "vless link (ipv4): see ${links_file}"
                else
                    echo "vless link (ipv4): n/a"
                fi
                if [[ -n "$vless_v6" && "$vless_v6" != "null" ]]; then
                    echo "vless link (ipv6): see ${links_file}"
                fi
                if [[ -n "$raw_v4" && "$raw_v4" != "null" ]]; then
                    echo "raw xray (ipv4): ${raw_v4}"
                fi
                if [[ -n "$raw_v6" && "$raw_v6" != "null" ]]; then
                    echo "raw xray (ipv6): ${raw_v6}"
                fi
                echo ""
            } >> "$tmp_client"
        done

        {
            echo "${rule58}"
            echo ""
        } >> "$tmp_client"
    done

    cat >> "$tmp_client" << EOF

💡 СОВЕТЫ ПО ИСПОЛЬЗОВАНИЮ:

• Начните с Config 1 (⭐ ГЛАВНЫЙ) - самый стабильный
• Config 2 используйте как резервный
• При блокировках переключайтесь между конфигами
• Периодически меняйте конфиги для безопасности
• В часы пиковой нагрузки используйте IPv6 (если доступен)

🔒 УЛУЧШЕНИЯ БЕЗОПАСНОСТИ (v4.0):

✓ Minisign проверка Xray (защита от supply chain атак)
✓ xhttp-first strongest direct stack для reality
✓ vless encryption + ${XRAY_DIRECT_FLOW:-xtls-rprx-vision}
✓ rescue-профиль packet-up для сложных сетей
✓ emergency-профиль stream-up + browser dialer
✓ Динамический Reality dest port (обход port-based блокировок)
✓ Spider Mode v2 (приоритетные домены)
✓ Раздельные порты IPv4/IPv6 (избегание конфликтов)
✓ Расширенный health monitoring

📊 ДИАГНОСТИКА:

Проверить статус:       systemctl status xray
Посмотреть логи:        journalctl -u xray -f
Тест конфигурации:      xray -test -c /etc/xray/config.json
Проверить порты:        ss -tlnp | grep xray
Health monitoring лог:  tail -f ${HEALTH_LOG}

🔄 ОБНОВЛЕНИЕ:

Для обновления Xray до новой версии выполните: sudo xray-reality.sh update

Авто-обновления настроены через systemd timer.

${rule58}

⚠️  ВАЖНО:

• НЕ делитесь файлом keys.txt - он содержит приватные ключи!
• Делитесь только clients.txt с доверенными пользователями
• Регулярно проверяйте логи на наличие аномалий
• При подозрении на компрометацию - пересоздайте конфиги

${rule58}
EOF

    mv "$tmp_client" "$client_file"
    chmod 640 "$client_file"
    chown "root:${XRAY_GROUP}" "$client_file" 2> /dev/null || true
}

render_clients_links_txt_from_json() {
    local json_file="$1"
    local links_file="$2"
    local rule58
    rule58="$(ui_rule_string 58)"

    if ! jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
        log ERROR "Некорректный JSON-источник для clients-links.txt: ${json_file}"
        return 1
    fi

    local server_ipv4 server_ipv6 generated
    server_ipv4=$(jq -r '.server_ipv4 // empty' "$json_file" 2> /dev/null || true)
    server_ipv6=$(jq -r '.server_ipv6 // empty' "$json_file" 2> /dev/null || true)
    generated=$(jq -r '.generated // empty' "$json_file" 2> /dev/null || true)

    [[ -n "$server_ipv4" ]] || server_ipv4="${SERVER_IP:-unknown}"
    [[ -n "$server_ipv6" ]] || server_ipv6="N/A"
    generated=$(printf '%s' "$generated" | tr -s '[:space:]' ' ')
    generated=$(trim_ws "$generated")
    [[ -n "$generated" ]] || generated="$(format_generated_timestamp)"

    backup_file "$links_file"
    local tmp_links
    tmp_links=$(mktemp "${links_file}.tmp.XXXXXX")

    local header_title="Network Stealth Core ${SCRIPT_VERSION} - QUICK VLESS LINKS"
    local header_width
    header_width=$(ui_box_width_for_lines 60 90 "$header_title")

    {
        printf '%s\n' "$(ui_box_border_string top "$header_width")"
        printf '%s\n' "$(ui_box_line_string "$header_title" "$header_width")"
        printf '%s\n' "$(ui_box_border_string bottom "$header_width")"
        echo ""
        echo "server: ${server_ipv4}"
        echo "server ipv6: ${server_ipv6}"
        echo "generated: ${generated}"
        echo ""
        echo "этот файл нужен для быстрого копирования vless-ссылок после установки."
        echo "подробное описание профилей смотри в ${XRAY_KEYS}/clients.txt"
        echo "emergency-профиль даётся только как raw xray json."
        echo ""
        echo "${rule58}"
        echo ""
    } > "$tmp_links"

    local config_count
    config_count=$(jq -r '.configs | length' "$json_file" 2> /dev/null || echo 0)

    local i
    for ((i = 0; i < config_count; i++)); do
        local domain port_v4 port_v6
        domain=$(jq -r ".configs[$i].domain // \"unknown\"" "$json_file" 2> /dev/null || echo "unknown")
        port_v4=$(jq -r ".configs[$i].port_ipv4 // \"N/A\"" "$json_file" 2> /dev/null || echo "N/A")
        port_v6=$(jq -r ".configs[$i].port_ipv6 // empty | tostring" "$json_file" 2> /dev/null || true)
        [[ -n "$port_v6" && "$port_v6" != "null" ]] || port_v6="N/A"

        local priority=""
        if [[ $i -eq 0 ]]; then
            priority=" * primary"
        elif [[ $i -eq 1 ]]; then
            priority=" ~ spare"
        fi

        {
            echo "Config $((i + 1)): ${domain}${priority}"
            echo "Port IPv4: ${port_v4}"
            echo "Port IPv6: ${port_v6}"
            echo ""
        } >> "$tmp_links"

        local variant_count
        variant_count=$(jq -r ".configs[$i].variants | length" "$json_file" 2> /dev/null || echo 0)
        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local j
        for ((j = 0; j < variant_count; j++)); do
            local variant_key variant_mode variant_category vless_v4 vless_v6 raw_v4 raw_v6 requires_browser_dialer
            variant_key=$(jq -r ".configs[$i].variants[$j].key // .configs[$i].recommended_variant // \"recommended\"" "$json_file" 2> /dev/null || echo "recommended")
            variant_mode=$(jq -r ".configs[$i].variants[$j].mode // empty" "$json_file" 2> /dev/null || true)
            variant_category=$(jq -r ".configs[$i].variants[$j].category // empty" "$json_file" 2> /dev/null || true)
            vless_v4=$(jq -r ".configs[$i].variants[$j].vless_v4 // empty" "$json_file" 2> /dev/null || true)
            vless_v6=$(jq -r ".configs[$i].variants[$j].vless_v6 // empty" "$json_file" 2> /dev/null || true)
            raw_v4=$(jq -r ".configs[$i].variants[$j].xray_client_file_v4 // empty" "$json_file" 2> /dev/null || true)
            raw_v6=$(jq -r ".configs[$i].variants[$j].xray_client_file_v6 // empty" "$json_file" 2> /dev/null || true)
            requires_browser_dialer=$(jq -r ".configs[$i].variants[$j].requires.browser_dialer // false" "$json_file" 2> /dev/null || echo "false")

            {
                printf 'variant: %s' "$(client_variant_title "$variant_key")"
                if [[ -n "$variant_category" && "$variant_category" != "null" ]]; then
                    printf ' | %s' "$variant_category"
                fi
                if [[ -n "$variant_mode" && "$variant_mode" != "null" ]]; then
                    printf ' | mode=%s' "$variant_mode"
                fi
                printf '\n'

                if [[ "$requires_browser_dialer" == "true" ]]; then
                    echo "raw xray only (browser dialer required)"
                else
                    if [[ -n "$vless_v4" && "$vless_v4" != "null" ]]; then
                        echo "vless ipv4:"
                        printf '%s\n' "$vless_v4"
                    else
                        echo "vless ipv4: n/a"
                    fi
                    if [[ -n "$vless_v6" && "$vless_v6" != "null" ]]; then
                        echo "vless ipv6:"
                        printf '%s\n' "$vless_v6"
                    fi
                fi

                if [[ -n "$raw_v4" && "$raw_v4" != "null" ]]; then
                    echo "raw xray ipv4: ${raw_v4}"
                fi
                if [[ -n "$raw_v6" && "$raw_v6" != "null" ]]; then
                    echo "raw xray ipv6: ${raw_v6}"
                fi
                echo ""
            } >> "$tmp_links"
        done

        {
            echo "${rule58}"
            echo ""
        } >> "$tmp_links"
    done

    mv "$tmp_links" "$links_file"
    chmod 640 "$links_file"
    chown "root:${XRAY_GROUP}" "$links_file" 2> /dev/null || true
}

secure_clients_json_permissions() {
    local json_file="$1"
    [[ -f "$json_file" ]] || return 0

    chmod 640 "$json_file" 2> /dev/null || true
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
            chown "root:${XRAY_GROUP}" "$json_file" 2> /dev/null || true
        else
            chown root:root "$json_file" 2> /dev/null || true
        fi
    fi
}

save_client_configs() {
    log STEP "Сохраняем клиентские конфигурации..."

    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
    local client_links_file="${XRAY_KEYS}/clients-links.txt"
    local json_file="${XRAY_KEYS}/clients.json"
    local rule58
    rule58="$(ui_rule_string 58)"

    mkdir -p "$(dirname "$keys_file")"

    local required_count="$NUM_CONFIGS"
    if ((required_count < 1)); then
        log WARN "Нет конфигураций для сохранения клиентов"
        return 0
    fi

    if [[ ${#UUIDS[@]} -lt $required_count || ${#PUBLIC_KEYS[@]} -lt $required_count || ${#SHORT_IDS[@]} -lt $required_count ]]; then
        log WARN "Недостаточно данных для генерации клиентских конфигов; файлы оставлены без изменений"
        return 0
    fi

    local i
    for ((i = 0; i < required_count; i++)); do
        if [[ -z "${PUBLIC_KEYS[$i]:-}" ]]; then
            log WARN "Публичные ключи не найдены - пропускаем генерацию clients.txt"
            return 0
        fi
    done

    backup_file "$keys_file"
    local tmp_keys
    tmp_keys=$(mktemp "${keys_file}.tmp.XXXXXX")
    cat > "$tmp_keys" << EOF
$(ui_box_border_string top 60)
$(ui_box_line_string "Network Stealth Core ${SCRIPT_VERSION} - SERVER KEYS (KEEP SECRET!)" 60)
$(ui_box_border_string bottom 60)

Server IPv4: ${SERVER_IP}
Server IPv6: ${SERVER_IP6:-N/A}
Generated: $(format_generated_timestamp)

EOF

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${CONFIG_DOMAINS[$i]:-unknown}"
        local provider_family="${CONFIG_PROVIDER_FAMILIES[$i]:-}"
        local vless_encryption="${CONFIG_VLESS_ENCRYPTIONS[$i]:-none}"
        local vless_decryption="${CONFIG_VLESS_DECRYPTIONS[$i]:-none}"
        if [[ -z "$provider_family" ]]; then
            provider_family="$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")"
        fi
        cat >> "$tmp_keys" << EOF
${rule58}
Config $((i + 1)):
${rule58}
Domain:      ${domain}
Provider:    ${provider_family}
Private Key: ${PRIVATE_KEYS[$i]}
Public Key:  ${PUBLIC_KEYS[$i]}
UUID:        ${UUIDS[$i]}
ShortID:     ${SHORT_IDS[$i]}
Port IPv4:   ${PORTS[$i]}
Port IPv6:   ${PORTS_V6[$i]:-N/A}
Flow:        ${XRAY_DIRECT_FLOW:-xtls-rprx-vision}
VLESS Decryption: ${vless_decryption}
VLESS Encryption: ${vless_encryption}

EOF
    done

    mv "$tmp_keys" "$keys_file"
    chmod 400 "$keys_file"
    chown root:root "$keys_file" 2> /dev/null || true

    local json_configs
    json_configs=$(jq -n '[]')
    local -a qr_links_v4=()
    local -a qr_links_v6=()
    local link_prefix
    link_prefix=$(client_link_prefix_for_tier "$DOMAIN_TIER")
    local raw_xray_dir="${XRAY_KEYS}/export/raw-xray"
    mkdir -p "$raw_xray_dir"
    find "$raw_xray_dir" -maxdepth 1 -type f -name 'config-*.json' -delete 2> /dev/null || true

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${CONFIG_DOMAINS[$i]:-unknown}"
        local sni="${CONFIG_SNIS[$i]:-$domain}"
        local fp="${CONFIG_FPS[$i]:-chrome}"
        local transport_value="${TRANSPORT:-xhttp}"
        local transport_endpoint="${CONFIG_TRANSPORT_ENDPOINTS[$i]:-/edge/api/default}"
        local transport_extra_value="$transport_endpoint"
        local provider_family="${CONFIG_PROVIDER_FAMILIES[$i]:-}"
        local vless_encryption="${CONFIG_VLESS_ENCRYPTIONS[$i]:-none}"
        local vless_decryption="${CONFIG_VLESS_DECRYPTIONS[$i]:-none}"
        local direct_flow="${XRAY_DIRECT_FLOW:-xtls-rprx-vision}"
        [[ -n "$provider_family" ]] || provider_family="$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")"

        local clean_name
        clean_name=$(echo "$domain" | sed 's/www\.//; s/\./-/g')

        local endpoint="$transport_endpoint"
        if [[ "$transport_value" == "http2" ]]; then
            endpoint=$(grpc_service_to_http2_path "$transport_endpoint")
        fi
        transport_extra_value="$endpoint"
        local variants='[]'
        local default_variant_key="recommended"
        local primary_vless_v4=""
        local primary_vless_v6=""
        local variant_key variant_mode
        while IFS=$'\t' read -r variant_key variant_mode; do
            [[ -n "$variant_key" ]] || continue
            local variant_label variant_note variant_name variant_category
            local variant_generates_link variant_requires_browser_dialer variant_import_hint
            variant_label=$(client_variant_title "$variant_key")
            variant_note=$(client_variant_note "$variant_key")
            variant_category=$(client_variant_category "$variant_key")
            variant_generates_link=$(client_variant_generates_link "$variant_key")
            variant_requires_browser_dialer=$(client_variant_requires_browser_dialer "$variant_key")
            variant_import_hint=$(client_variant_import_hint "$variant_key")
            variant_name="${link_prefix}-${clean_name}-$(client_variant_link_suffix "$variant_key" "$((i + 1))")"

            local variant_v4 variant_v6
            variant_v4=""
            variant_v6=""
            if [[ "$variant_generates_link" == "true" ]]; then
                variant_v4=$(build_client_vless_link \
                    "${SERVER_IP:-$domain}" "${PORTS[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                    "$transport_value" "$endpoint" "$variant_mode" "$variant_name")

                if [[ "$HAS_IPV6" == true && -n "${SERVER_IP6:-}" && -n "${PORTS_V6[$i]:-}" ]]; then
                    variant_v6=$(build_client_vless_link \
                        "[${SERVER_IP6}]" "${PORTS_V6[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                        "$transport_value" "$endpoint" "$variant_mode" "${variant_name}-v6")
                fi
            fi

            local raw_v4="" raw_v6=""
            if [[ "$transport_value" == "xhttp" ]]; then
                local raw_server_v4="${SERVER_IP:-$domain}"
                local raw_server_v6="${SERVER_IP6:-$domain}"
                if [[ "$variant_requires_browser_dialer" == "true" ]]; then
                    raw_server_v4="$domain"
                    raw_server_v6="$domain"
                fi
                raw_v4="${XRAY_KEYS}/export/$(variant_xray_relative_path "$((i + 1))" "$variant_key" "ipv4")"
                mkdir -p "$(dirname "$raw_v4")"
                build_xray_client_variant_json \
                    "$raw_server_v4" "${PORTS[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                    "$transport_value" "$endpoint" "$variant_mode" "$vless_encryption" "$variant_requires_browser_dialer" "$direct_flow" |
                    jq '.' | atomic_write "$raw_v4" 0640
                chown "root:${XRAY_GROUP}" "$raw_v4" 2> /dev/null || true

                if [[ "$HAS_IPV6" == true && -n "${PORTS_V6[$i]:-}" ]]; then
                    raw_v6="${XRAY_KEYS}/export/$(variant_xray_relative_path "$((i + 1))" "$variant_key" "ipv6")"
                    mkdir -p "$(dirname "$raw_v6")"
                    build_xray_client_variant_json \
                        "$raw_server_v6" "${PORTS_V6[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                        "$transport_value" "$endpoint" "$variant_mode" "$vless_encryption" "$variant_requires_browser_dialer" "$direct_flow" |
                        jq '.' | atomic_write "$raw_v6" 0640
                    chown "root:${XRAY_GROUP}" "$raw_v6" 2> /dev/null || true
                fi
            fi

            if [[ "$variant_key" == "recommended" && -n "$variant_v4" ]]; then
                default_variant_key="$variant_key"
                primary_vless_v4="$variant_v4"
                primary_vless_v6="$variant_v6"
            elif [[ -z "$primary_vless_v4" && -n "$variant_v4" ]]; then
                default_variant_key="$variant_key"
                primary_vless_v4="$variant_v4"
                primary_vless_v6="$variant_v6"
            fi

            variants=$(jq -n \
                --argjson arr "$variants" \
                --arg key "$variant_key" \
                --arg category "$variant_category" \
                --arg label "$variant_label" \
                --arg note "$variant_note" \
                --arg mode "$variant_mode" \
                --arg transport "$transport_value" \
                --arg endpoint "$endpoint" \
                --arg import_hint "$variant_import_hint" \
                --arg flow "$direct_flow" \
                --arg vless_encryption "$vless_encryption" \
                --arg raw_v4 "$raw_v4" \
                --arg raw_v6 "$raw_v6" \
                --arg vless_v4 "$variant_v4" \
                --arg vless_v6 "$variant_v6" \
                --argjson requires_browser_dialer "$variant_requires_browser_dialer" \
                --argjson requires_vless_encryption "$(if [[ "$vless_encryption" != "none" ]]; then echo true; else echo false; fi)" \
                '$arr + [{
                    key: $key,
                    category: $category,
                    label: $label,
                    note: $note,
                    mode: (if ($mode | length) > 0 then $mode else null end),
                    transport: $transport,
                    transport_endpoint: $endpoint,
                    requires: {
                        browser_dialer: $requires_browser_dialer,
                        vless_encryption: $requires_vless_encryption,
                        flow: $flow
                    },
                    import_hint: $import_hint,
                    vless_v4: $vless_v4,
                    vless_v6: (if ($vless_v6 | length) > 0 then $vless_v6 else null end),
                    vless_encryption: $vless_encryption,
                    xray_client_file_v4: (if ($raw_v4 | length) > 0 then $raw_v4 else null end),
                    xray_client_file_v6: (if ($raw_v6 | length) > 0 then $raw_v6 else null end)
                }]')
        done < <(client_variant_catalog "$transport_value")

        qr_links_v4+=("$primary_vless_v4")
        qr_links_v6+=("$primary_vless_v6")

        json_configs=$(jq -n \
            --argjson arr "$json_configs" \
            --arg name "Config $((i + 1))" \
            --arg domain "$domain" \
            --arg sni "$sni" \
            --arg fp "$fp" \
            --arg transport "$transport_value" \
            --arg transport_endpoint "$transport_extra_value" \
            --arg provider_family "$provider_family" \
            --arg uuid "${UUIDS[$i]}" \
            --arg short_id "${SHORT_IDS[$i]}" \
            --arg public_key "${PUBLIC_KEYS[$i]}" \
            --arg port_ipv4 "${PORTS[$i]}" \
            --arg port_ipv6 "${PORTS_V6[$i]:-}" \
            --arg default_variant_key "$default_variant_key" \
            --arg vless_v4 "$primary_vless_v4" \
            --arg vless_v6 "$primary_vless_v6" \
            --arg dest "${CONFIG_DESTS[$i]:-${domain}:443}" \
            --arg primary_rank "$((i + 1))" \
            --arg flow "$direct_flow" \
            --arg vless_encryption "$vless_encryption" \
            --arg vless_decryption "$vless_decryption" \
            --argjson variants "$variants" \
            '$arr + [{
                name: $name,
                domain: $domain,
                provider_family: $provider_family,
                primary_rank: ($primary_rank|tonumber),
                dest: $dest,
                sni: $sni,
                fingerprint: $fp,
                transport: $transport,
                transport_endpoint: $transport_endpoint,
                uuid: $uuid,
                short_id: $short_id,
                public_key: $public_key,
                port_ipv4: ($port_ipv4|tonumber),
                port_ipv6: (if ($port_ipv6 | length) > 0 then ($port_ipv6 | tonumber?) else null end),
                flow: $flow,
                vless_encryption: $vless_encryption,
                vless_decryption: $vless_decryption,
                vless_v4: $vless_v4,
                vless_v6: (if ($vless_v6 | length) > 0 then $vless_v6 else null end),
                recommended_variant: $default_variant_key,
                variants: $variants
            }]')
    done

    backup_file "$json_file"
    local json_output
    json_output=$(jq -n \
        --arg server_ipv4 "$SERVER_IP" \
        --arg server_ipv6 "${SERVER_IP6:-}" \
        --arg generated "$(format_generated_timestamp)" \
        --arg transport "$TRANSPORT" \
        --arg spider "$SPIDER_MODE" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        --arg contract_version "${STEALTH_CONTRACT_VERSION:-7.1.0}" \
        --argjson configs "$json_configs" \
        '{
            schema_version: 3,
            stealth_contract_version: $contract_version,
            server_ipv4: $server_ipv4,
            server_ipv6: (if ($server_ipv6 | length) > 0 then $server_ipv6 else null end),
            generated: $generated,
            transport: $transport,
            xray_min_version: $min_version,
            spider_mode: ($spider == "true"),
            configs: $configs
        }')
    printf '%s\n' "$json_output" | atomic_write "$json_file" 0640
    secure_clients_json_permissions "$json_file"
    render_clients_txt_from_json "$json_file" "$client_file"
    render_clients_links_txt_from_json "$json_file" "${XRAY_KEYS}/clients-links.txt"

    if [[ "$QR_ENABLED" == "true" ]] || { [[ "$QR_ENABLED" == "auto" ]] && command -v qrencode > /dev/null 2>&1; }; then
        if command -v qrencode > /dev/null 2>&1; then
            local qr_dir="${XRAY_KEYS}/qr"
            mkdir -p "$qr_dir"
            for ((i = 0; i < NUM_CONFIGS; i++)); do
                if [[ -n "${qr_links_v4[$i]:-}" ]]; then
                    qrencode -o "${qr_dir}/config-${i}-v4.png" -s 6 -m 2 "${qr_links_v4[$i]}" > /dev/null 2>&1 || true
                fi
                if [[ -n "${qr_links_v6[$i]:-}" ]]; then
                    qrencode -o "${qr_dir}/config-${i}-v6.png" -s 6 -m 2 "${qr_links_v6[$i]}" > /dev/null 2>&1 || true
                fi
            done
            log OK "QR-коды сохранены в ${qr_dir}"
        else
            log WARN "qrencode не найден; QR-коды пропущены"
        fi
    fi

    log OK "Конфигурации сохранены"
}

update_env_num_configs() {
    local env_file="$1"
    local total="$2"
    [[ -f "$env_file" ]] || return 0
    [[ "$total" =~ ^[0-9]+$ ]] || return 1

    backup_file "$env_file"
    local tmp_env
    tmp_env=$(mktemp "${env_file}.tmp.XXXXXX")

    awk -v total="$total" '
        BEGIN { has_num=0; has_xnum=0 }
        /^NUM_CONFIGS=/ {
            print "NUM_CONFIGS=\"" total "\""
            has_num=1
            next
        }
        /^XRAY_NUM_CONFIGS=/ {
            print "XRAY_NUM_CONFIGS=\"" total "\""
            has_xnum=1
            next
        }
        { print }
        END {
            if (!has_num) {
                print "NUM_CONFIGS=\"" total "\""
            }
            if (!has_xnum) {
                print "XRAY_NUM_CONFIGS=\"" total "\""
            }
        }
    ' "$env_file" > "$tmp_env"

    mv "$tmp_env" "$env_file"
    chmod 600 "$env_file"
}

validate_clients_json_file() {
    local json_file="$1"
    local clients_shape_filter=""
    [[ -f "$json_file" ]] || return 0

    clients_shape_filter=$(
        cat << 'JQ'
type == "object"
and (.configs | type == "array")
and ((.schema_version // 0) >= 2)
and ((.configs | length) < 1 or ([.configs[]? | (((.variants | arrays | length) // 0) >= 1)] | all))
JQ
    )

    if jq -e "$clients_shape_filter" "$json_file" > /dev/null 2>&1; then
        return 0
    fi

    local normalized_json=""
    if jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(cat "$json_file")
    elif jq -e 'type == "array"' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq -n --slurpfile cfg "$json_file" '{configs: $cfg[0]}')
    elif jq -e 'type == "object" and (.profiles | type == "array")' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq '. + {configs: .profiles} | del(.profiles)' "$json_file")
    else
        normalized_json='{"configs":[]}'
        log WARN "Некорректный формат ${json_file}; файл будет пересоздан в схеме .configs"
    fi

    normalized_json=$(printf '%s\n' "$normalized_json" | jq '
        .schema_version = 3
        | .stealth_contract_version = (.stealth_contract_version // "7.1.0")
        | .transport = (.transport // "xhttp")
        | .xray_min_version = (.xray_min_version // "25.9.5")
        | .configs = (
            (.configs // [])
            | map(
                . as $cfg
                | ($cfg.variants // []) as $variants
                | .provider_family = ($cfg.provider_family // ($cfg.domain // ""))
                | .primary_rank = ($cfg.primary_rank // 0)
                | .transport = ($cfg.transport // $cfg.transport_type // ($variants[0].transport // "xhttp"))
                | .transport_endpoint = ($cfg.transport_endpoint // $cfg.grpc_service // ($variants[0].transport_endpoint // ""))
                | .flow = ($cfg.flow // "xtls-rprx-vision")
                | .vless_encryption = ($cfg.vless_encryption // "none")
                | .vless_decryption = ($cfg.vless_decryption // "none")
                | .recommended_variant = ($cfg.recommended_variant // ($variants[0].key // "recommended"))
                | .variants = (
                    if ($variants | type == "array" and ($variants | length) > 0) then
                        ($variants | map(
                            .key = (.key // "recommended")
                            | .category = (.category // (
                                if .key == "recommended" then "direct"
                                elif .key == "rescue" then "fallback"
                                elif .key == "emergency" then "emergency"
                                else "legacy"
                                end
                              ))
                            | .label = (.label // .key // "recommended")
                            | .note = (.note // "normalized from legacy schema")
                            | .transport = (.transport // $cfg.transport // "xhttp")
                            | .transport_endpoint = (.transport_endpoint // $cfg.transport_endpoint // "")
                            | .requires = (.requires // {
                                browser_dialer: (.key == "emergency"),
                                vless_encryption: (($cfg.vless_encryption // "none") != "none"),
                                flow: ($cfg.flow // "xtls-rprx-vision")
                              })
                            | .import_hint = (.import_hint // (
                                if .key == "emergency" then "raw xray json only; requires browser dialer on the client"
                                elif .key == "rescue" then "use raw xray json if the normal variant is unstable"
                                else "import raw xray json when possible; vless link is secondary"
                                end
                              ))
                        ))
                    else
                        [{
                            key: (.recommended_variant // "recommended"),
                            category: "direct",
                            label: (.recommended_variant // "recommended"),
                            note: "normalized from legacy schema",
                            mode: (if (.transport // "xhttp") == "xhttp" then "auto" else null end),
                            transport: (.transport // "xhttp"),
                            transport_endpoint: (.transport_endpoint // .grpc_service // ""),
                            requires: {
                                browser_dialer: false,
                                vless_encryption: (($cfg.vless_encryption // "none") != "none"),
                                flow: ($cfg.flow // "xtls-rprx-vision")
                            },
                            import_hint: "import raw xray json when possible; vless link is secondary",
                            vless_v4: (.vless_v4 // null),
                            vless_v6: (.vless_v6 // null),
                            xray_client_file_v4: null,
                            xray_client_file_v6: null
                        }]
                    end
                )
            )
        )')

    if ! printf '%s\n' "$normalized_json" | jq -e 'type == "object" and (.configs | type == "array") and (.schema_version // 0) >= 3' > /dev/null 2>&1; then
        log ERROR "Не удалось привести ${json_file} к схеме .configs"
        return 1
    fi

    printf '%s\n' "$normalized_json" | atomic_write "$json_file" 0640
    secure_clients_json_permissions "$json_file"
    log WARN "Нормализован legacy-формат ${json_file} -> schema v3"
    return 0
}

collect_fallback_public_keys_from_artifacts() {
    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
    local client_links_file="${XRAY_KEYS}/clients-links.txt"
    local json_file="${XRAY_KEYS}/clients.json"
    local required_count="${1:-0}"

    local -a from_keys=()
    local -a from_json=()
    local -a from_clients=()

    if [[ -f "$keys_file" ]]; then
        mapfile -t from_keys < <(awk -F'Public Key:[[:space:]]*' '
            /^Public Key:/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                if ($2 != "") print $2
            }
        ' "$keys_file")
    fi

    if [[ -f "$json_file" ]] && command -v jq > /dev/null 2>&1; then
        mapfile -t from_json < <(jq -r '.configs[]?.public_key // empty' "$json_file" 2> /dev/null)
    fi

    if [[ -f "$client_file" ]]; then
        local line params pbk seen=" "
        while IFS= read -r line; do
            [[ "$line" == vless://* ]] || continue
            [[ "$line" == *"@["* ]] && continue
            params="${line#*\?}"
            params="${params%%#*}"
            pbk=$(get_query_param "$params" "pbk" || true)
            [[ -n "$pbk" ]] || continue
            [[ " $seen " == *" $pbk "* ]] && continue
            seen="${seen}${pbk} "
            from_clients+=("$pbk")
        done < "$client_file"
    fi

    if [[ -f "$client_links_file" ]]; then
        local line params pbk seen_links=" "
        while IFS= read -r line; do
            [[ "$line" == vless://* ]] || continue
            [[ "$line" == *"@["* ]] && continue
            params="${line#*\?}"
            params="${params%%#*}"
            pbk=$(get_query_param "$params" "pbk" || true)
            [[ -n "$pbk" ]] || continue
            [[ " $seen_links " == *" $pbk "* ]] && continue
            seen_links="${seen_links}${pbk} "
            from_clients+=("$pbk")
        done < "$client_links_file"
    fi

    local -a best=("${from_keys[@]}")
    if ((${#from_json[@]} > ${#best[@]})); then
        best=("${from_json[@]}")
    fi
    if ((${#from_clients[@]} > ${#best[@]})); then
        best=("${from_clients[@]}")
    fi

    if ((required_count > 0 && ${#best[@]} > required_count)); then
        best=("${best[@]:0:required_count}")
    fi
    printf '%s\n' "${best[@]}"
}

derive_public_key_from_private_key() {
    local private_key="$1"
    [[ -n "$private_key" ]] || return 1
    [[ -x "$XRAY_BIN" ]] || return 1

    local key_output pub
    if ! key_output=$("$XRAY_BIN" x25519 -i "$private_key" 2>&1); then
        debug_file "xray x25519 -i failed while deriving public key: ${key_output}"
        return 1
    fi
    pub=$(printf '%s\n' "$key_output" | sed -n 's/.*Public key:[[:space:]]*//p' | head -n 1 | tr -d '\r')

    if [[ "$pub" =~ ^[A-Za-z0-9_-]{20,128}$ ]]; then
        printf '%s\n' "$pub"
        return 0
    fi
    return 1
}

build_public_keys_for_current_config() {
    local required_count=${#PORTS[@]}
    if ((required_count < 1)); then
        log ERROR "Нет портов в текущей конфигурации для восстановления public keys"
        return 1
    fi

    local -a fallback_public_keys=()
    mapfile -t fallback_public_keys < <(collect_fallback_public_keys_from_artifacts "$required_count")

    PUBLIC_KEYS=()
    local i pub
    for ((i = 0; i < required_count; i++)); do
        pub=""
        if [[ -n "${PRIVATE_KEYS[$i]:-}" ]]; then
            pub=$(derive_public_key_from_private_key "${PRIVATE_KEYS[$i]}" || true)
        fi
        if [[ -z "$pub" && -n "${fallback_public_keys[$i]:-}" ]]; then
            pub="${fallback_public_keys[$i]}"
        fi
        if [[ -z "$pub" ]]; then
            log ERROR "Не удалось восстановить public key для конфига #$((i + 1))"
            return 1
        fi
        PUBLIC_KEYS+=("$pub")
    done
    return 0
}

client_artifacts_missing() {
    local -a files=(
        "${XRAY_KEYS}/keys.txt"
        "${XRAY_KEYS}/clients.txt"
        "${XRAY_KEYS}/clients-links.txt"
        "${XRAY_KEYS}/clients.json"
    )
    local missing=false
    local file
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log WARN "Отсутствует клиентский артефакт: ${file}"
            missing=true
        fi
    done
    [[ "$missing" == true ]]
}

client_artifacts_inconsistent() {
    local expected_count="${1:-0}"
    if [[ ! "$expected_count" =~ ^[0-9]+$ ]] || ((expected_count < 1)); then
        expected_count="${#PORTS[@]}"
    fi
    if ((expected_count < 1)); then
        return 1
    fi

    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
    local client_links_file="${XRAY_KEYS}/clients-links.txt"
    local json_file="${XRAY_KEYS}/clients.json"

    local inconsistent=false
    local count

    if [[ -f "$keys_file" ]]; then
        count=$(awk '/^Private Key:/ {c++} END {print c+0}' "$keys_file")
        if ((count != expected_count)); then
            log WARN "keys.txt рассинхронизирован: ${count}/${expected_count}"
            inconsistent=true
        fi
    fi

    if [[ -f "$client_file" ]]; then
        count=$(awk '/Config [0-9]+:/ {c++} END {print c+0}' "$client_file")
        if ((count != expected_count)); then
            log WARN "clients.txt рассинхронизирован: ${count}/${expected_count} секций"
            inconsistent=true
        fi
    fi

    if [[ -f "$client_links_file" ]]; then
        count=$(awk '/^Config [0-9]+:/ {c++} END {print c+0}' "$client_links_file")
        if ((count != expected_count)); then
            log WARN "clients-links.txt рассинхронизирован: ${count}/${expected_count} секций"
            inconsistent=true
        fi
    fi

    if [[ -f "$json_file" ]]; then
        if ! jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
            log WARN "clients.json имеет некорректную схему"
            inconsistent=true
        else
            count=$(jq -r '.configs | length' "$json_file" 2> /dev/null || echo 0)
            if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count != expected_count)); then
                log WARN "clients.json рассинхронизирован: ${count}/${expected_count}"
                inconsistent=true
            fi
        fi
    fi

    [[ "$inconsistent" == true ]]
}

client_artifacts_ready_for_self_check() {
    local json_file="${XRAY_KEYS}/clients.json"
    local capabilities_file="${XRAY_KEYS}/export/capabilities.json"

    if client_artifacts_missing; then
        return 1
    fi
    if client_artifacts_inconsistent "${#PORTS[@]}"; then
        return 1
    fi
    if [[ ! -f "$capabilities_file" ]]; then
        log WARN "Отсутствует capability matrix: ${capabilities_file}"
        return 1
    fi
    if ! jq -e '.formats | type == "array"' "$capabilities_file" > /dev/null 2>&1; then
        log WARN "capabilities.json имеет некорректную схему"
        return 1
    fi
    if ! jq -e '
        type == "object"
        and (.configs | type == "array")
        and ([.configs[] | .variants[] | (.xray_client_file_v4 // empty)] | map(select(length > 0)) | length) >= 1
    ' "$json_file" > /dev/null 2>&1; then
        log WARN "clients.json не содержит пригодных raw xray variants для self-check"
        return 1
    fi
    local declared_raw
    while IFS= read -r declared_raw; do
        [[ -n "$declared_raw" ]] || continue
        if [[ ! -f "$declared_raw" ]]; then
            log WARN "Отсутствует raw xray variant: ${declared_raw}"
            return 1
        fi
    done < <(jq -r '.configs[] | .variants[] | .xray_client_file_v4 // empty, .xray_client_file_v6 // empty' "$json_file" 2> /dev/null)
    return 0
}

ensure_self_check_artifacts_ready() {
    if client_artifacts_ready_for_self_check; then
        return 0
    fi
    log INFO "Артефакты self-check отсутствуют или устарели; пересобираем"
    rebuild_client_artifacts_from_config || return 1
    client_artifacts_ready_for_self_check
}

rebuild_client_artifacts_from_loaded_state() {
    save_client_configs || return 1
    if declare -F export_all_configs > /dev/null 2>&1; then
        export_all_configs || return 1
    fi
    return 0
}

rebuild_client_artifacts_from_config() {
    log STEP "Пересобираем клиентские артефакты из текущей конфигурации..."

    load_existing_ports_from_config
    load_existing_metadata_from_config
    load_keys_from_config

    NUM_CONFIGS=${#PORTS[@]}
    if ((NUM_CONFIGS < 1)); then
        log ERROR "Не найдены inbounds для пересборки клиентских артефактов"
        return 1
    fi

    if ! build_public_keys_for_current_config; then
        return 1
    fi

    rebuild_client_artifacts_from_loaded_state || return 1
    log OK "Клиентские артефакты пересобраны из config.json"
    return 0
}
