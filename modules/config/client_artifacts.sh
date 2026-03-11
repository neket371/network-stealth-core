#!/usr/bin/env bash
# shellcheck shell=bash

: "${UI_BOX_H:=─}"
: "${XRAY_KEYS:=/etc/xray/private/keys}"
: "${SCRIPT_VERSION:=unknown}"
: "${XRAY_GROUP:=xray}"
: "${DOMAIN_TIER:=tier_ru}"
: "${HAS_IPV6:=false}"
: "${QR_ENABLED:=false}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
if ! declare -p UUIDS > /dev/null 2>&1; then UUIDS=(); fi
if ! declare -p PUBLIC_KEYS > /dev/null 2>&1; then PUBLIC_KEYS=(); fi
if ! declare -p SHORT_IDS > /dev/null 2>&1; then SHORT_IDS=(); fi
if ! declare -p PORTS > /dev/null 2>&1; then PORTS=(); fi
if ! declare -p PORTS_V6 > /dev/null 2>&1; then PORTS_V6=(); fi

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
        recommended) printf '%s' "основная (recommended)" ;;
        rescue) printf '%s' "запасная (rescue)" ;;
        emergency) printf '%s' "аварийная (emergency)" ;;
        *) printf '%s' "стандартная (standard)" ;;
    esac
}

client_variant_category() {
    local key="${1:-standard}"
    case "$key" in
        recommended) printf '%s' "прямой режим" ;;
        rescue) printf '%s' "запасной режим" ;;
        emergency) printf '%s' "аварийный режим" ;;
        *) printf '%s' "legacy-режим" ;;
    esac
}

client_variant_note() {
    local key="${1:-standard}"
    case "$key" in
        recommended) printf '%s' "обычный старт: это основной вариант" ;;
        rescue) printf '%s' "включай, если основная ссылка не проходит" ;;
        emergency) printf '%s' "только если обычный и запасной варианты не помогли" ;;
        *) printf '%s' "legacy-совместимый профиль" ;;
    esac
}

print_client_config_box() {
    local title="$1"
    shift || true
    local width
    width=$(ui_box_width_for_lines 36 72 "$title" "$@")
    local top sep bottom
    top=$(ui_box_border_string top "$width")
    sep=$(ui_box_line_string "$(ui_repeat_char "$UI_BOX_H" "$width")" "$width")
    bottom=$(ui_box_border_string bottom "$width")

    echo "$top"
    printf '%s\n' "$(ui_box_line_string "$title" "$width")"
    echo "$sep"

    local line
    for line in "$@"; do
        printf '%s\n' "$(ui_box_line_string "$line" "$width")"
    done

    echo "$bottom"
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

    backup_file "$client_file"
    local tmp_client
    tmp_client=$(mktemp "${client_file}.tmp.XXXXXX")

    local header_title="network stealth core ${SCRIPT_VERSION} - клиентские конфиги"
    local header_width
    header_width=$(ui_box_width_for_lines 60 90 "$header_title")

    {
        printf '%s\n' "$(ui_box_border_string top "$header_width")"
        printf '%s\n' "$(ui_box_line_string "$header_title" "$header_width")"
        printf '%s\n' "$(ui_box_border_string bottom "$header_width")"
        echo ""
        echo "сервер ipv4: ${server_ipv4}"
        echo "сервер ipv6: ${server_ipv6}"
        echo "создано: ${generated}"
        echo "транспорт: ${transport_summary}"
        echo "серверный стек: reality + xhttp + vless encryption + ${XRAY_DIRECT_FLOW:-xtls-rprx-vision}"
        echo "spider mode: $([[ "${spider_mode}" == "true" ]] && echo "включён" || echo "выключен")"
        echo "быстрые ссылки: ${links_file}"
        echo ""
        echo "как подключаться:"
        echo "1. сначала открой ${links_file} и импортируй основную ссылку"
        echo "2. если основная не идёт — пробуй запасную"
        echo "3. аварийная нужна редко: только raw xray json + browser dialer"
        echo ""
        echo "${rule58}"
        echo ""
    } > "$tmp_client"

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
            priority=" ★ основной"
        elif [[ $i -eq 1 ]]; then
            priority=" ☆ запасной"
        fi

        local transport_display transport_extra_label
        transport_display=$(transport_display_name "$transport_value")
        case "${transport_value,,}" in
            xhttp) transport_extra_label="путь xhttp" ;;
            http2 | h2 | http/2) transport_extra_label="путь http/2" ;;
            *) transport_extra_label="grpc service" ;;
        esac

        {
            print_client_config_box "config $((i + 1)): ${domain}${priority}" \
                "порт ipv4: ${port_v4}" \
                "порт ipv6: ${port_v6}" \
                "sni: ${sni}" \
                "провайдер: ${provider_family}" \
                "отпечаток: ${fp}" \
                "транспорт: ${transport_display}" \
                "${transport_extra_label}: ${endpoint}" \
                "flow: ${flow_value}" \
                "vless encryption: ${encryption_value}"
            echo "ссылки: ${links_file}"
            echo ""
            echo "варианты:"
        } >> "$tmp_client"

        local variant_count
        variant_count=$(jq -r ".configs[$i].variants | length" "$json_file" 2> /dev/null || echo 0)
        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local j
        for ((j = 0; j < variant_count; j++)); do
            local variant_key variant_note variant_mode raw_v4 raw_v6 requires_browser_dialer
            variant_key=$(jq -r ".configs[$i].variants[$j].key // .configs[$i].recommended_variant // \"recommended\"" "$json_file" 2> /dev/null || echo "recommended")
            variant_note=$(jq -r ".configs[$i].variants[$j].note // empty" "$json_file" 2> /dev/null || true)
            variant_mode=$(jq -r ".configs[$i].variants[$j].mode // empty" "$json_file" 2> /dev/null || true)
            raw_v4=$(jq -r ".configs[$i].variants[$j].xray_client_file_v4 // empty" "$json_file" 2> /dev/null || true)
            raw_v6=$(jq -r ".configs[$i].variants[$j].xray_client_file_v6 // empty" "$json_file" 2> /dev/null || true)
            requires_browser_dialer=$(jq -r ".configs[$i].variants[$j].requires.browser_dialer // false" "$json_file" 2> /dev/null || echo "false")
            [[ -n "$variant_note" && "$variant_note" != "null" ]] || variant_note=$(client_variant_note "$variant_key")

            {
                echo "- вариант: $(client_variant_title "$variant_key")"
                if [[ -n "$variant_mode" && "$variant_mode" != "null" ]]; then
                    echo "  режим: ${variant_mode}"
                fi
                echo "  когда: ${variant_note}"
                if [[ "$requires_browser_dialer" == "true" ]]; then
                    echo "  импорт: только raw xray json"
                    echo "  browser dialer: нужен"
                else
                    echo "  ссылка: см. ${links_file}"
                fi
                if [[ -n "$raw_v4" && "$raw_v4" != "null" ]]; then
                    echo "  raw xray ipv4: ${raw_v4}"
                fi
                if [[ -n "$raw_v6" && "$raw_v6" != "null" ]]; then
                    echo "  raw xray ipv6: ${raw_v6}"
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

управление:
- статус: xray-reality.sh status
- логи: xray-reality.sh logs
- обновить: xray-reality.sh update
- удалить: xray-reality.sh uninstall
- raw xray и canary: ${XRAY_KEYS}/export/

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

    local header_title="network stealth core ${SCRIPT_VERSION} - быстрые ссылки"
    local header_width
    header_width=$(ui_box_width_for_lines 60 90 "$header_title")

    {
        printf '%s\n' "$(ui_box_border_string top "$header_width")"
        printf '%s\n' "$(ui_box_line_string "$header_title" "$header_width")"
        printf '%s\n' "$(ui_box_border_string bottom "$header_width")"
        echo ""
        echo "сервер ipv4: ${server_ipv4}"
        echo "сервер ipv6: ${server_ipv6}"
        echo "создано: ${generated}"
        echo ""
        echo "что здесь делать:"
        echo "1. сначала импортируй основную ссылку"
        echo "2. если не идёт — импортируй запасную"
        echo "3. аварийная даётся только как raw xray json"
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
            priority=" ★ основной"
        elif [[ $i -eq 1 ]]; then
            priority=" ☆ запасной"
        fi

        {
            echo "config $((i + 1)): ${domain}${priority}"
            echo "порт ipv4: ${port_v4}"
            echo "порт ipv6: ${port_v6}"
            echo ""
        } >> "$tmp_links"

        local variant_count
        variant_count=$(jq -r ".configs[$i].variants | length" "$json_file" 2> /dev/null || echo 0)
        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local j
        for ((j = 0; j < variant_count; j++)); do
            local variant_key vless_v4 vless_v6 raw_v4 raw_v6 requires_browser_dialer
            variant_key=$(jq -r ".configs[$i].variants[$j].key // .configs[$i].recommended_variant // \"recommended\"" "$json_file" 2> /dev/null || echo "recommended")
            vless_v4=$(jq -r ".configs[$i].variants[$j].vless_v4 // empty" "$json_file" 2> /dev/null || true)
            vless_v6=$(jq -r ".configs[$i].variants[$j].vless_v6 // empty" "$json_file" 2> /dev/null || true)
            raw_v4=$(jq -r ".configs[$i].variants[$j].xray_client_file_v4 // empty" "$json_file" 2> /dev/null || true)
            raw_v6=$(jq -r ".configs[$i].variants[$j].xray_client_file_v6 // empty" "$json_file" 2> /dev/null || true)
            requires_browser_dialer=$(jq -r ".configs[$i].variants[$j].requires.browser_dialer // false" "$json_file" 2> /dev/null || echo "false")

            {
                case "$variant_key" in
                    recommended) echo "основная ссылка:" ;;
                    rescue) echo "запасная ссылка:" ;;
                    emergency) echo "аварийный raw xray:" ;;
                    *) echo "$(client_variant_title "$variant_key"):" ;;
                esac

                if [[ "$requires_browser_dialer" == "true" ]]; then
                    echo "только raw xray json + browser dialer"
                    if [[ -n "$raw_v4" && "$raw_v4" != "null" ]]; then
                        echo "ipv4: ${raw_v4}"
                    fi
                    if [[ -n "$raw_v6" && "$raw_v6" != "null" ]]; then
                        echo "ipv6: ${raw_v6}"
                    fi
                else
                    if [[ -n "$vless_v4" && "$vless_v4" != "null" ]]; then
                        echo "ipv4:"
                        printf '%s\n' "$vless_v4"
                    else
                        echo "ipv4: n/a"
                    fi
                    if [[ -n "$vless_v6" && "$vless_v6" != "null" ]]; then
                        echo "ipv6:"
                        printf '%s\n' "$vless_v6"
                    fi
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
            endpoint=$(legacy_transport_endpoint_to_http2_path "$transport_endpoint")
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
        --arg spider "${SPIDER_MODE:-false}" \
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

    local section_pattern='([Cc]onfig|конфиг) [0-9]+:'

    if [[ -f "$client_file" ]]; then
        count=$(awk -v pattern="$section_pattern" '$0 ~ pattern {c++} END {print c+0}' "$client_file")
        if ((count != expected_count)); then
            log WARN "clients.txt рассинхронизирован: ${count}/${expected_count} секций"
            inconsistent=true
        fi
    fi

    if [[ -f "$client_links_file" ]]; then
        count=$(awk -v pattern="$section_pattern" '$0 ~ pattern {c++} END {print c+0}' "$client_links_file")
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
