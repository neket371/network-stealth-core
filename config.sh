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

CONFIG_CLIENT_ARTIFACTS_MODULE="$SCRIPT_DIR/modules/config/client_artifacts.sh"
if [[ ! -f "$CONFIG_CLIENT_ARTIFACTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_CLIENT_ARTIFACTS_MODULE="$XRAY_DATA_DIR/modules/config/client_artifacts.sh"
fi
if [[ ! -f "$CONFIG_CLIENT_ARTIFACTS_MODULE" ]]; then
    log ERROR "Не найден модуль client artifacts: $CONFIG_CLIENT_ARTIFACTS_MODULE"
    exit 1
fi
# shellcheck source=modules/config/client_artifacts.sh
source "$CONFIG_CLIENT_ARTIFACTS_MODULE"

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
                transport_endpoint=$(select_legacy_transport_endpoint "$domain")
            fi
        fi

        local payload="$transport_endpoint"
        if [[ "$target_transport" == "http2" ]]; then
            payload=$(legacy_transport_endpoint_to_http2_path "$transport_endpoint")
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
