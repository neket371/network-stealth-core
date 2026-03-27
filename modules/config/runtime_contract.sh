#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154 # sourced config modules intentionally consume runtime globals from lib.sh/globals_contract.sh

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

    transport_normalize_assign transport_mode "$transport_mode"

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
                decryption: $decryption_value
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
    if [[ -n "$version" ]] && version_lt "$version" "${XRAY_CLIENT_MIN_VERSION}"; then
        log ERROR "Xray ${version} слишком старый для strongest direct stack"
        log ERROR "требуется версия >= ${XRAY_CLIENT_MIN_VERSION}"
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
    if transport_is_xhttp "${TRANSPORT:-xhttp}"; then
        MUX_ENABLED=false
        # shellcheck disable=SC2034 # global runtime state consumed by save_environment and tests
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
        # shellcheck disable=SC2034 # global runtime state consumed by save_environment and tests
        MUX_CONCURRENCY=$(rand_between "$MUX_CONCURRENCY_MIN" "$MUX_CONCURRENCY_MAX")
    else
        # shellcheck disable=SC2034 # global runtime state consumed by save_environment and tests
        MUX_CONCURRENCY=0
    fi
}
