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
    local grpc_service="$8"
    local keepalive="$9"
    local grpc_idle="${10}"
    local grpc_health="${11}"
    local transport_mode="${12:-$TRANSPORT}"
    local transport_label="${13:-$grpc_service}"

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
        --arg grpc "$grpc_service" \
        --arg h2_path "$transport_label" \
        --arg h2_host "$primary_sni" \
        --arg transport "$transport_mode" \
        --argjson grpc_idle "$grpc_idle" \
        --argjson grpc_health "$grpc_health" \
        --argjson keepalive "$keepalive" \
        '{
            port: ($port|tonumber),
            listen: "0.0.0.0",
            protocol: "vless",
            settings: {
                clients: [{id: $uuid}],
                decryption: "none"
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
                + (if $transport == "http2" then
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
                            serviceName: $grpc,
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
    CONFIG_GRPC_SERVICES=()
    CONFIG_FPS=()

    setup_mux_settings
    check_xray_version_for_config_generation

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
        CONFIG_GRPC_SERVICES+=("$PROFILE_GRPC")
        CONFIG_FPS+=("$PROFILE_FP")

        local sni_count
        sni_count=$(echo "$PROFILE_SNI_JSON" | jq 'length' 2> /dev/null || echo 1)
        log INFO "Config $((i + 1)): ${domain} → ${PROFILE_DEST} (${PROFILE_FP}, ${TRANSPORT}, SNIs: ${sni_count})"

        local inbound_v4
        inbound_v4=$(generate_profile_inbound_json \
            "${PORTS[$i]}" "${UUIDS[$i]}" "${PRIVATE_KEYS[$i]}" "${SHORT_IDS[$i]}")

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
        write_env_kv DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv XRAY_DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv MUX_MODE "$MUX_MODE"
        write_env_kv TRANSPORT "$TRANSPORT"
        write_env_kv XRAY_TRANSPORT "$TRANSPORT"
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
        write_env_kv LOG_RETENTION_DAYS "$LOG_RETENTION_DAYS"
        write_env_kv LOG_MAX_SIZE_MB "$LOG_MAX_SIZE_MB"
        write_env_kv HEALTH_LOG "$HEALTH_LOG"
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

render_clients_txt_from_json() {
    local json_file="$1"
    local client_file="$2"
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
    transport_raw=$(jq -r '.transport // "grpc"' "$json_file" 2> /dev/null || echo "grpc")
    spider_mode=$(jq -r '.spider_mode // false' "$json_file" 2> /dev/null || echo "false")

    [[ -n "$server_ipv4" ]] || server_ipv4="${SERVER_IP:-unknown}"
    [[ -n "$server_ipv6" ]] || server_ipv6="N/A"
    generated=$(printf '%s' "$generated" | tr -s '[:space:]' ' ')
    generated=$(trim_ws "$generated")
    [[ -n "$generated" ]] || generated="$(format_generated_timestamp)"

    local transport_summary="gRPC"
    case "${transport_raw,,}" in
        http2 | h2 | http/2) transport_summary="HTTP/2" ;;
        *) ;;
    esac

    local mux_summary="Disabled"
    if [[ "${MUX_ENABLED:-false}" == true ]]; then
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
Security: Reality + TLS 1.3
DPI Bypass: Reality (built-in)
Spider Mode: $([[ "${spider_mode}" == "true" ]] && echo "Enabled" || echo "Disabled")

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
✓ Fragment: tlshello (100-200 bytes, interval 10-20ms)
✓ Fragment packets: 5-10, endpoint-independent-nat

${rule58}

🔗 КОНФИГУРАЦИИ:

EOF

    local config_count
    config_count=$(jq -r '.configs | length' "$json_file" 2> /dev/null || echo 0)

    local i
    for ((i = 0; i < config_count; i++)); do
        local domain sni fp transport_value endpoint port_v4 port_v6 vless_v4 vless_v6
        domain=$(jq -r ".configs[$i].domain // \"unknown\"" "$json_file" 2> /dev/null || echo "unknown")
        sni=$(jq -r ".configs[$i].sni // .configs[$i].domain // \"unknown\"" "$json_file" 2> /dev/null || echo "unknown")
        fp=$(jq -r ".configs[$i].fingerprint // \"chrome\"" "$json_file" 2> /dev/null || echo "chrome")
        transport_value=$(jq -r ".configs[$i].transport // \"grpc\"" "$json_file" 2> /dev/null || echo "grpc")
        endpoint=$(jq -r ".configs[$i].transport_endpoint // .configs[$i].grpc_service // \"-\"" "$json_file" 2> /dev/null || echo "-")
        port_v4=$(jq -r ".configs[$i].port_ipv4 // \"N/A\"" "$json_file" 2> /dev/null || echo "N/A")
        port_v6=$(jq -r ".configs[$i].port_ipv6 // empty | tostring" "$json_file" 2> /dev/null || true)
        vless_v4=$(jq -r ".configs[$i].vless_v4 // empty" "$json_file" 2> /dev/null || true)
        vless_v6=$(jq -r ".configs[$i].vless_v6 // empty" "$json_file" 2> /dev/null || true)

        [[ -n "$port_v6" && "$port_v6" != "null" ]] || port_v6="N/A"

        local priority=""
        if [[ $i -eq 0 ]]; then
            priority=" * ГЛАВНЫЙ"
        elif [[ $i -eq 1 ]]; then
            priority=" ~ РЕЗЕРВНЫЙ"
        fi

        local transport_display="gRPC"
        local transport_extra_key="gRPC Service"
        case "${transport_value,,}" in
            http2 | h2 | http/2)
                transport_display="HTTP/2"
                transport_extra_key="HTTP/2 Path"
                ;;
            *) ;;
        esac

        {
            echo "$BOX60_TOP"
            box60_line "Config $((i + 1)): ${domain}${priority}"
            echo "$BOX60_SEP"
            box60_line "Port IPv4: ${port_v4}"
            box60_line "Port IPv6: ${port_v6}"
            box60_line "SNI: ${sni}"
            box60_line "Fingerprint: ${fp}"
            box60_line "Transport: ${transport_display}"
            box60_line "${transport_extra_key}: ${endpoint}"
            echo "$BOX60_BOT"
            echo ""
            echo "📱 VLESS Link (IPv4):"
            echo "${vless_v4}"
            echo ""
        } >> "$tmp_client"

        if [[ -n "$vless_v6" && "$vless_v6" != "null" ]]; then
            {
                echo "📱 VLESS Link (IPv6):"
                echo "${vless_v6}"
                echo ""
            } >> "$tmp_client"
        fi

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
✓ Реалистичные API service names (для gRPC/HTTP2)
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
    chown "root:${XRAY_GROUP}" "$client_file"
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
        cat >> "$tmp_keys" << EOF
${rule58}
Config $((i + 1)):
${rule58}
Private Key: ${PRIVATE_KEYS[$i]}
Public Key:  ${PUBLIC_KEYS[$i]}
UUID:        ${UUIDS[$i]}
ShortID:     ${SHORT_IDS[$i]}
Port IPv4:   ${PORTS[$i]}
Port IPv6:   ${PORTS_V6[$i]:-N/A}

EOF
    done

    mv "$tmp_keys" "$keys_file"
    chmod 400 "$keys_file"
    chown root:root "$keys_file"

    local json_configs
    json_configs=$(jq -n '[]')
    local -a vless_links_v4=()
    local -a vless_links_v6=()
    local link_prefix
    link_prefix=$(client_link_prefix_for_tier "$DOMAIN_TIER")

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${CONFIG_DOMAINS[$i]:-unknown}"
        local sni="${CONFIG_SNIS[$i]:-$domain}"
        local fp="${CONFIG_FPS[$i]:-chrome}"
        local grpc="${CONFIG_GRPC_SERVICES[$i]:-GunService}"
        local transport_extra_value="$grpc"

        local clean_name
        clean_name=$(echo "$domain" | sed 's/www\.//; s/\./-/g')

        local endpoint="$grpc"
        if [[ "$TRANSPORT" == "http2" ]]; then
            endpoint=$(grpc_service_to_http2_path "$grpc")
        fi
        transport_extra_value="$endpoint"
        local params
        params=$(build_vless_query_params "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" "$TRANSPORT" "$endpoint")

        local vless_v4="vless://${UUIDS[$i]}@${SERVER_IP}:${PORTS[$i]}?${params}#${link_prefix}-${clean_name}-$((i + 1))"
        vless_links_v4+=("$vless_v4")

        if [[ "$HAS_IPV6" == true && -n "${SERVER_IP6:-}" && -n "${PORTS_V6[$i]:-}" ]]; then
            local vless_v6="vless://${UUIDS[$i]}@[${SERVER_IP6}]:${PORTS_V6[$i]}?${params}#${link_prefix}-${clean_name}-v6-$((i + 1))"
            vless_links_v6+=("$vless_v6")
        else
            vless_links_v6+=("")
        fi

        json_configs=$(jq -n \
            --argjson arr "$json_configs" \
            --arg name "Config $((i + 1))" \
            --arg domain "$domain" \
            --arg sni "$sni" \
            --arg fp "$fp" \
            --arg transport "$TRANSPORT" \
            --arg grpc "$transport_extra_value" \
            --arg uuid "${UUIDS[$i]}" \
            --arg short_id "${SHORT_IDS[$i]}" \
            --arg public_key "${PUBLIC_KEYS[$i]}" \
            --arg port_ipv4 "${PORTS[$i]}" \
            --arg port_ipv6 "${PORTS_V6[$i]:-}" \
            --arg vless_v4 "$vless_v4" \
            --arg vless_v6 "${vless_links_v6[$i]}" \
            '$arr + [{
                name: $name,
                domain: $domain,
                sni: $sni,
                fingerprint: $fp,
                transport: $transport,
                grpc_service: $grpc,
                transport_endpoint: $grpc,
                uuid: $uuid,
                short_id: $short_id,
                public_key: $public_key,
                port_ipv4: ($port_ipv4|tonumber),
                port_ipv6: (if ($port_ipv6 | length) > 0 then ($port_ipv6 | tonumber?) else null end),
                vless_v4: $vless_v4,
                vless_v6: (if ($vless_v6 | length) > 0 then $vless_v6 else null end)
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
        --argjson configs "$json_configs" \
        '{
            server_ipv4: $server_ipv4,
            server_ipv6: (if ($server_ipv6 | length) > 0 then $server_ipv6 else null end),
            generated: $generated,
            transport: $transport,
            spider_mode: ($spider == "true"),
            configs: $configs
        }')
    printf '%s\n' "$json_output" | atomic_write "$json_file" 0640
    secure_clients_json_permissions "$json_file"
    render_clients_txt_from_json "$json_file" "$client_file"

    if [[ "$QR_ENABLED" == "true" ]] || { [[ "$QR_ENABLED" == "auto" ]] && command -v qrencode > /dev/null 2>&1; }; then
        if command -v qrencode > /dev/null 2>&1; then
            local qr_dir="${XRAY_KEYS}/qr"
            mkdir -p "$qr_dir"
            for ((i = 0; i < NUM_CONFIGS; i++)); do
                if [[ -n "${vless_links_v4[$i]:-}" ]]; then
                    qrencode -o "${qr_dir}/config-${i}-v4.png" -s 6 -m 2 "${vless_links_v4[$i]}" > /dev/null 2>&1 || true
                fi
                if [[ -n "${vless_links_v6[$i]:-}" ]]; then
                    qrencode -o "${qr_dir}/config-${i}-v6.png" -s 6 -m 2 "${vless_links_v6[$i]}" > /dev/null 2>&1 || true
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
    [[ -f "$json_file" ]] || return 0

    if jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
        return 0
    fi

    local normalized_json=""
    if jq -e 'type == "array"' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq -n --slurpfile cfg "$json_file" '{configs: $cfg[0]}')
    elif jq -e 'type == "object" and (.profiles | type == "array")' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq '. + {configs: .profiles} | del(.profiles)' "$json_file")
    else
        normalized_json='{"configs":[]}'
        log WARN "Некорректный формат ${json_file}; файл будет пересоздан в схеме .configs"
    fi

    if ! printf '%s\n' "$normalized_json" | jq -e 'type == "object" and (.configs | type == "array")' > /dev/null 2>&1; then
        log ERROR "Не удалось привести ${json_file} к схеме .configs"
        return 1
    fi

    printf '%s\n' "$normalized_json" | atomic_write "$json_file" 0640
    secure_clients_json_permissions "$json_file"
    log WARN "Нормализован legacy-формат ${json_file} -> объект с .configs"
    return 0
}

collect_fallback_public_keys_from_artifacts() {
    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
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
        local line params pbk
        while IFS= read -r line; do
            [[ "$line" == vless://* ]] || continue
            [[ "$line" == *"@["* ]] && continue
            params="${line#*\?}"
            params="${params%%#*}"
            pbk=$(get_query_param "$params" "pbk" || true)
            [[ -n "$pbk" ]] && from_clients+=("$pbk")
        done < "$client_file"
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
        count=$(awk '/^vless:\/\// { if ($0 !~ /@\[/) c++ } END {print c+0}' "$client_file")
        if ((count != expected_count)); then
            log WARN "clients.txt рассинхронизирован: ${count}/${expected_count} IPv4 ссылок"
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

    save_client_configs || return 1
    if declare -F export_all_configs > /dev/null 2>&1; then
        export_all_configs || return 1
    fi
    log OK "Клиентские артефакты пересобраны из config.json"
    return 0
}
