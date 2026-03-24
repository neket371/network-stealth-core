#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154 # sourced config modules intentionally consume runtime globals from lib.sh/globals_contract.sh

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
            # legacy-only compatibility branch for migrate-stealth / explicit legacy rebuilds.
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
        --arg min_version "${XRAY_CLIENT_MIN_VERSION}" \
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

write_client_variant_json_file() {
    local target_file="$1"
    shift

    mkdir -p "$(dirname "$target_file")" || {
        log ERROR "Не удалось создать каталог для raw Xray файла: ${target_file}"
        return 1
    }

    if ! build_xray_client_variant_json "$@" | jq '.' > "$target_file"; then
        rm -f "$target_file"
        log ERROR "Не удалось собрать raw Xray конфиг: ${target_file}"
        return 1
    fi

    chmod 640 "$target_file" 2> /dev/null || true
    chown "root:${XRAY_GROUP}" "$target_file" 2> /dev/null || true
}

client_json_config_rows_tsv() {
    local json_file="$1"
    jq -r \
        --arg default_flow "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}" \
        '
        .configs
        | to_entries[]
        | [
            (.key | tostring),
            (.value.domain // "unknown"),
            (.value.sni // .value.domain // "unknown"),
            (.value.fingerprint // "chrome"),
            (.value.transport // "xhttp"),
            (.value.transport_endpoint // .value.grpc_service // "-"),
            ((.value.port_ipv4 // "N/A") | tostring),
            ((.value.port_ipv6 // null) | if . == null then "" else tostring end),
            (.value.provider_family // "-"),
            (.value.flow // $default_flow),
            (.value.vless_encryption // "none"),
            (((.value.variants // []) | if length > 0 then length else 1 end) | tostring)
        ]
        | map(tostring)
        | join("\u001f")
        ' "$json_file"
}

client_json_variant_rows_tsv() {
    local json_file="$1"
    local config_index="$2"
    jq -r \
        --argjson idx "$config_index" \
        '
        .configs[$idx] as $cfg
        | (($cfg.variants // []) | if length > 0 then . else [
            {
                key: ($cfg.recommended_variant // "recommended"),
                note: null,
                mode: null,
                requires: { browser_dialer: false },
                xray_client_file_v4: null,
                xray_client_file_v6: null,
                vless_v4: ($cfg.vless_v4 // null),
                vless_v6: ($cfg.vless_v6 // null)
            }
          ] end)
        | .[]
        | [
            (.key // ($cfg.recommended_variant // "recommended")),
            (.note // ""),
            (.mode // ""),
            (.xray_client_file_v4 // ""),
            (.xray_client_file_v6 // ""),
            ((.requires.browser_dialer // false) | tostring),
            (.vless_v4 // ""),
            (.vless_v6 // "")
        ]
        | map(tostring)
        | join("\u001f")
        ' "$json_file"
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

    local config_index domain sni fp transport_value endpoint port_v4 port_v6 provider_family flow_value encryption_value variant_count
    while IFS=$'\x1f' read -r config_index domain sni fp transport_value endpoint port_v4 port_v6 provider_family flow_value encryption_value variant_count; do
        [[ -n "$config_index" ]] || continue
        config_index="${config_index//$'\r'/}"
        domain="${domain//$'\r'/}"
        sni="${sni//$'\r'/}"
        fp="${fp//$'\r'/}"
        transport_value="${transport_value//$'\r'/}"
        endpoint="${endpoint//$'\r'/}"
        port_v4="${port_v4//$'\r'/}"
        port_v6="${port_v6//$'\r'/}"
        provider_family="${provider_family//$'\r'/}"
        flow_value="${flow_value//$'\r'/}"
        encryption_value="${encryption_value//$'\r'/}"
        variant_count="${variant_count//$'\r'/}"
        [[ -n "$port_v6" ]] || port_v6="N/A"

        local priority=""
        if [[ "$config_index" -eq 0 ]]; then
            priority=" ★ основной"
        elif [[ "$config_index" -eq 1 ]]; then
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
            print_client_config_box "config $((config_index + 1)): ${domain}${priority}" \
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

        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local variant_key variant_note variant_mode raw_v4 raw_v6 requires_browser_dialer
        while IFS=$'\x1f' read -r variant_key variant_note variant_mode raw_v4 raw_v6 requires_browser_dialer _variant_v4 _variant_v6; do
            [[ -n "$variant_key" ]] || continue
            variant_key="${variant_key//$'\r'/}"
            variant_note="${variant_note//$'\r'/}"
            variant_mode="${variant_mode//$'\r'/}"
            raw_v4="${raw_v4//$'\r'/}"
            raw_v6="${raw_v6//$'\r'/}"
            requires_browser_dialer="${requires_browser_dialer//$'\r'/}"
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
        done < <(client_json_variant_rows_tsv "$json_file" "$config_index")

        {
            echo "${rule58}"
            echo ""
        } >> "$tmp_client"
    done < <(client_json_config_rows_tsv "$json_file")

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

    local config_index domain sni fp transport_value endpoint port_v4 port_v6 provider_family flow_value encryption_value variant_count
    while IFS=$'\x1f' read -r config_index domain sni fp transport_value endpoint port_v4 port_v6 provider_family flow_value encryption_value variant_count; do
        [[ -n "$config_index" ]] || continue
        config_index="${config_index//$'\r'/}"
        domain="${domain//$'\r'/}"
        port_v4="${port_v4//$'\r'/}"
        port_v6="${port_v6//$'\r'/}"
        variant_count="${variant_count//$'\r'/}"
        [[ -n "$port_v6" ]] || port_v6="N/A"

        local priority=""
        if [[ "$config_index" -eq 0 ]]; then
            priority=" ★ основной"
        elif [[ "$config_index" -eq 1 ]]; then
            priority=" ☆ запасной"
        fi

        {
            echo "config $((config_index + 1)): ${domain}${priority}"
            echo "порт ipv4: ${port_v4}"
            echo "порт ipv6: ${port_v6}"
            echo ""
        } >> "$tmp_links"

        if [[ ! "$variant_count" =~ ^[0-9]+$ ]] || ((variant_count < 1)); then
            variant_count=1
        fi

        local variant_key variant_note variant_mode raw_v4 raw_v6 requires_browser_dialer vless_v4 vless_v6
        while IFS=$'\x1f' read -r variant_key variant_note variant_mode raw_v4 raw_v6 requires_browser_dialer vless_v4 vless_v6; do
            [[ -n "$variant_key" ]] || continue
            variant_key="${variant_key//$'\r'/}"
            raw_v4="${raw_v4//$'\r'/}"
            raw_v6="${raw_v6//$'\r'/}"
            requires_browser_dialer="${requires_browser_dialer//$'\r'/}"
            vless_v4="${vless_v4//$'\r'/}"
            vless_v6="${vless_v6//$'\r'/}"

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
        done < <(client_json_variant_rows_tsv "$json_file" "$config_index")

        {
            echo "${rule58}"
            echo ""
        } >> "$tmp_links"
    done < <(client_json_config_rows_tsv "$json_file")

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

save_client_configs_validate_prerequisites() {
    local required_count="$1"
    if ((required_count < 1)); then
        log WARN "Нет конфигураций для сохранения клиентов"
        return 2
    fi

    if [[ ${#UUIDS[@]} -lt $required_count || ${#PUBLIC_KEYS[@]} -lt $required_count || ${#SHORT_IDS[@]} -lt $required_count ]]; then
        log WARN "Недостаточно данных для генерации клиентских конфигов; файлы оставлены без изменений"
        return 2
    fi

    local i
    for ((i = 0; i < required_count; i++)); do
        if [[ -z "${PUBLIC_KEYS[$i]:-}" ]]; then
            log WARN "Публичные ключи не найдены - пропускаем генерацию clients.txt"
            return 2
        fi
    done
    return 0
}

save_client_configs_write_server_keys() {
    local keys_file="$1"
    local rule58="$2"
    local required_count="$3"

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

    local i
    for ((i = 0; i < required_count; i++)); do
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
}

build_client_variant_inventory_fragment() {
    local variant_key="$1"
    local variant_category="$2"
    local variant_label="$3"
    local variant_note="$4"
    local variant_mode="$5"
    local transport_value="$6"
    local endpoint="$7"
    local variant_import_hint="$8"
    local direct_flow="$9"
    local vless_encryption="${10}"
    local raw_v4="${11}"
    local raw_v6="${12}"
    local variant_v4="${13}"
    local variant_v6="${14}"
    local variant_requires_browser_dialer="${15}"
    local requires_vless_encryption=false
    if [[ "$vless_encryption" != "none" ]]; then
        requires_vless_encryption=true
    fi

    jq -n \
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
        --argjson requires_vless_encryption "$requires_vless_encryption" \
        '{
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
        }'
}

build_client_config_inventory_fragment() {
    local name="$1"
    local domain="$2"
    local sni="$3"
    local fp="$4"
    local transport_value="$5"
    local transport_endpoint="$6"
    local provider_family="$7"
    local uuid="$8"
    local short_id="$9"
    local public_key="${10}"
    local port_ipv4="${11}"
    local port_ipv6="${12}"
    local default_variant_key="${13}"
    local vless_v4="${14}"
    local vless_v6="${15}"
    local dest="${16}"
    local primary_rank="${17}"
    local direct_flow="${18}"
    local vless_encryption="${19}"
    local vless_decryption="${20}"
    local variants_json="${21}"

    jq -n \
        --arg name "$name" \
        --arg domain "$domain" \
        --arg sni "$sni" \
        --arg fp "$fp" \
        --arg transport "$transport_value" \
        --arg transport_endpoint "$transport_endpoint" \
        --arg provider_family "$provider_family" \
        --arg uuid "$uuid" \
        --arg short_id "$short_id" \
        --arg public_key "$public_key" \
        --arg port_ipv4 "$port_ipv4" \
        --arg port_ipv6 "$port_ipv6" \
        --arg default_variant_key "$default_variant_key" \
        --arg vless_v4 "$vless_v4" \
        --arg vless_v6 "$vless_v6" \
        --arg dest "$dest" \
        --arg primary_rank "$primary_rank" \
        --arg flow "$direct_flow" \
        --arg vless_encryption "$vless_encryption" \
        --arg vless_decryption "$vless_decryption" \
        --argjson variants "$variants_json" \
        '{
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
        }'
}

save_client_configs_build_inventory() {
    local required_count="$1"
    local out_json_configs_name="$2"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_qr_links_v4="$3"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_qr_links_v6="$4"
    local stage_export_root="${5:-${XRAY_KEYS}/export}"

    local json_configs_acc='[]'
    local link_prefix
    link_prefix=$(client_link_prefix_for_tier "$DOMAIN_TIER")
    local raw_xray_dir="${stage_export_root}/raw-xray"
    mkdir -p "$raw_xray_dir"
    local -a json_config_fragments=()

    local i
    for ((i = 0; i < required_count; i++)); do
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
        local -a variant_fragments=()
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
                local raw_relative_path=""
                local raw_target_v4=""
                local raw_target_v6=""
                if [[ "$variant_requires_browser_dialer" == "true" ]]; then
                    raw_server_v4="$domain"
                    raw_server_v6="$domain"
                fi
                raw_relative_path="$(variant_xray_relative_path "$((i + 1))" "$variant_key" "ipv4")"
                raw_v4="${XRAY_KEYS}/export/${raw_relative_path}"
                raw_target_v4="${stage_export_root}/${raw_relative_path}"
                write_client_variant_json_file \
                    "$raw_target_v4" \
                    "$raw_server_v4" "${PORTS[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                    "$transport_value" "$endpoint" "$variant_mode" "$vless_encryption" "$variant_requires_browser_dialer" "$direct_flow" || return 1

                if [[ "$HAS_IPV6" == true && -n "${PORTS_V6[$i]:-}" ]]; then
                    raw_relative_path="$(variant_xray_relative_path "$((i + 1))" "$variant_key" "ipv6")"
                    raw_v6="${XRAY_KEYS}/export/${raw_relative_path}"
                    raw_target_v6="${stage_export_root}/${raw_relative_path}"
                    write_client_variant_json_file \
                        "$raw_target_v6" \
                        "$raw_server_v6" "${PORTS_V6[$i]}" "${UUIDS[$i]}" "$sni" "$fp" "${PUBLIC_KEYS[$i]}" "${SHORT_IDS[$i]}" \
                        "$transport_value" "$endpoint" "$variant_mode" "$vless_encryption" "$variant_requires_browser_dialer" "$direct_flow" || return 1
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

            variant_fragments+=("$(build_client_variant_inventory_fragment \
                "$variant_key" "$variant_category" "$variant_label" "$variant_note" "$variant_mode" \
                "$transport_value" "$endpoint" "$variant_import_hint" "$direct_flow" "$vless_encryption" \
                "$raw_v4" "$raw_v6" "$variant_v4" "$variant_v6" "$variant_requires_browser_dialer")")
        done < <(client_variant_catalog "$transport_value")

        if ! variants=$(json_array_from_fragments "${variant_fragments[@]}"); then
            log ERROR "Не удалось собрать список client-variants для ${domain}"
            return 1
        fi

        out_qr_links_v4+=("$primary_vless_v4")
        out_qr_links_v6+=("$primary_vless_v6")

        json_config_fragments+=("$(build_client_config_inventory_fragment \
            "Config $((i + 1))" "$domain" "$sni" "$fp" "$transport_value" "$transport_extra_value" \
            "$provider_family" "${UUIDS[$i]}" "${SHORT_IDS[$i]}" "${PUBLIC_KEYS[$i]}" "${PORTS[$i]}" "${PORTS_V6[$i]:-}" \
            "$default_variant_key" "$primary_vless_v4" "$primary_vless_v6" "${CONFIG_DESTS[$i]:-${domain}:443}" "$((i + 1))" \
            "$direct_flow" "$vless_encryption" "$vless_decryption" "$variants")")
    done
    if ! json_configs_acc=$(json_array_from_fragments "${json_config_fragments[@]}"); then
        log ERROR "Не удалось собрать inventory client-configs"
        return 1
    fi
    printf -v "$out_json_configs_name" '%s' "$json_configs_acc"
}

build_clients_json_output() {
    local json_configs="$1"

    jq -n \
        --arg server_ipv4 "$SERVER_IP" \
        --arg server_ipv6 "${SERVER_IP6:-}" \
        --arg generated "$(format_generated_timestamp)" \
        --arg transport "$TRANSPORT" \
        --arg spider "${SPIDER_MODE:-false}" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION}" \
        --arg contract_version "${STEALTH_CONTRACT_VERSION}" \
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
        }'
}

client_artifacts_create_stage_dir() {
    mkdir -p "${XRAY_KEYS}" "${XRAY_KEYS}/export" || {
        log ERROR "Не удалось подготовить staging-каталог клиентских артефактов"
        return 1
    }

    local stage_root
    stage_root=$(mktemp -d "${XRAY_KEYS}/.client-artifacts.XXXXXX") || {
        log ERROR "Не удалось создать staging-каталог клиентских артефактов"
        return 1
    }
    printf '%s\n' "$stage_root"
}

client_artifacts_snapshot_target() {
    local target="$1"
    local backup_root="$2"
    local label="$3"
    local manifest_file="${backup_root}/manifest.env"

    mkdir -p "$backup_root" || return 1
    if [[ -e "$target" ]]; then
        rm -rf -- "${backup_root:?}/${label:?}" 2> /dev/null || true
        cp -a "$target" "${backup_root}/${label}" || return 1
        printf '%s=present\n' "$label" >> "$manifest_file"
    else
        printf '%s=absent\n' "$label" >> "$manifest_file"
    fi
}

client_artifacts_restore_target() {
    local target="$1"
    local backup_root="$2"
    local label="$3"
    local manifest_file="${backup_root}/manifest.env"
    local state=""

    if [[ -f "$manifest_file" ]]; then
        state=$(awk -F= -v key="$label" '$1 == key { value=$2 } END { if (value != "") print value }' "$manifest_file")
    fi

    case "$state" in
        present)
            mkdir -p "$(dirname "$target")" || return 1
            rm -rf -- "$target" 2> /dev/null || true
            cp -a "${backup_root}/${label}" "$target" || return 1
            ;;
        absent | "")
            rm -rf -- "$target" 2> /dev/null || true
            ;;
    esac
}

save_client_configs_stage_qr_artifacts() {
    local stage_root="$1"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n qr_links_v4_ref="$2"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n qr_links_v6_ref="$3"
    local i

    if [[ "$QR_ENABLED" != "true" ]] && { [[ "$QR_ENABLED" != "auto" ]] || ! command -v qrencode > /dev/null 2>&1; }; then
        return 0
    fi

    if ! command -v qrencode > /dev/null 2>&1; then
        log WARN "qrencode не найден; QR-коды пропущены"
        return 0
    fi

    local qr_dir="${stage_root}/qr"
    mkdir -p "$qr_dir" || {
        log ERROR "Не удалось создать staging-каталог QR-кодов"
        return 1
    }

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        if [[ -n "${qr_links_v4_ref[$i]:-}" ]]; then
            qrencode -o "${qr_dir}/config-${i}-v4.png" -s 6 -m 2 "${qr_links_v4_ref[$i]}" > /dev/null 2>&1 || true
        fi
        if [[ -n "${qr_links_v6_ref[$i]:-}" ]]; then
            qrencode -o "${qr_dir}/config-${i}-v6.png" -s 6 -m 2 "${qr_links_v6_ref[$i]}" > /dev/null 2>&1 || true
        fi
    done
}

save_client_configs_stage_inventory_outputs() {
    local stage_root="$1"
    local json_configs="$2"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n qr_links_v4_ref="$3"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n qr_links_v6_ref="$4"

    local json_stage="${stage_root}/clients.json"
    local client_stage="${stage_root}/clients.txt"
    local links_stage="${stage_root}/clients-links.txt"
    local json_output
    json_output=$(build_clients_json_output "$json_configs") || {
        log ERROR "Не удалось собрать clients.json в staging"
        return 1
    }

    if ! printf '%s\n' "$json_output" > "$json_stage"; then
        log ERROR "Не удалось записать staging clients.json"
        return 1
    fi

    if ! (
        log() { :; }
        backup_file() { :; }
        render_clients_txt_from_json "$json_stage" "$client_stage"
        render_clients_links_txt_from_json "$json_stage" "$links_stage"
    ); then
        log ERROR "Не удалось собрать staging client artifacts из clients.json"
        return 1
    fi

    save_client_configs_stage_qr_artifacts "$stage_root" qr_links_v4_ref qr_links_v6_ref
}

publish_staged_client_file() {
    local stage_file="$1"
    local target_file="$2"
    local mode="$3"
    local kind="${4:-text}"

    [[ -f "$stage_file" ]] || {
        log ERROR "Не найден staging-файл клиента: ${stage_file}"
        return 1
    }

    backup_file "$target_file"
    if ! cat -- "$stage_file" | atomic_write "$target_file" "$mode"; then
        log ERROR "Не удалось опубликовать клиентский артефакт: ${target_file}"
        return 1
    fi

    case "$kind" in
        json)
            secure_clients_json_permissions "$target_file"
            ;;
        text)
            chmod "$mode" "$target_file" 2> /dev/null || true
            chown "root:${XRAY_GROUP}" "$target_file" 2> /dev/null || true
            ;;
        *) ;;
    esac
}

publish_staged_client_directory() {
    local stage_dir="$1"
    local target_dir="$2"
    local label="$3"

    [[ -d "$stage_dir" ]] || return 0
    mkdir -p "$(dirname "$target_dir")" || {
        log ERROR "Не удалось подготовить каталог для ${label}: ${target_dir}"
        return 1
    }
    rm -rf -- "$target_dir" 2> /dev/null || true
    if ! mv -- "$stage_dir" "$target_dir"; then
        log ERROR "Не удалось опубликовать ${label}: ${target_dir}"
        return 1
    fi
}

restore_client_artifact_publish() {
    local backup_root="$1"
    local json_file="$2"
    local client_file="$3"
    local links_file="$4"
    local raw_xray_dir="$5"
    local qr_dir="$6"

    client_artifacts_restore_target "$json_file" "$backup_root" "clients.json" || return 1
    client_artifacts_restore_target "$client_file" "$backup_root" "clients.txt" || return 1
    client_artifacts_restore_target "$links_file" "$backup_root" "clients-links.txt" || return 1
    client_artifacts_restore_target "$raw_xray_dir" "$backup_root" "raw-xray" || return 1
    client_artifacts_restore_target "$qr_dir" "$backup_root" "qr" || return 1
}

save_client_configs_publish_staged_outputs() {
    local stage_root="$1"
    local json_file="$2"
    local client_file="$3"
    local links_file="${XRAY_KEYS}/clients-links.txt"
    local raw_xray_dir="${XRAY_KEYS}/export/raw-xray"
    local qr_dir="${XRAY_KEYS}/qr"
    local backup_root="${stage_root}/publish-backup"

    client_artifacts_snapshot_target "$json_file" "$backup_root" "clients.json" || return 1
    client_artifacts_snapshot_target "$client_file" "$backup_root" "clients.txt" || return 1
    client_artifacts_snapshot_target "$links_file" "$backup_root" "clients-links.txt" || return 1
    client_artifacts_snapshot_target "$raw_xray_dir" "$backup_root" "raw-xray" || return 1
    client_artifacts_snapshot_target "$qr_dir" "$backup_root" "qr" || return 1

    if ! publish_staged_client_directory "${stage_root}/export/raw-xray" "$raw_xray_dir" "raw-xray"; then
        restore_client_artifact_publish "$backup_root" "$json_file" "$client_file" "$links_file" "$raw_xray_dir" "$qr_dir" || true
        return 1
    fi
    if ! publish_staged_client_file "${stage_root}/clients.json" "$json_file" 0640 json; then
        restore_client_artifact_publish "$backup_root" "$json_file" "$client_file" "$links_file" "$raw_xray_dir" "$qr_dir" || true
        return 1
    fi
    if ! publish_staged_client_file "${stage_root}/clients.txt" "$client_file" 0640 text; then
        restore_client_artifact_publish "$backup_root" "$json_file" "$client_file" "$links_file" "$raw_xray_dir" "$qr_dir" || true
        return 1
    fi
    if ! publish_staged_client_file "${stage_root}/clients-links.txt" "$links_file" 0640 text; then
        restore_client_artifact_publish "$backup_root" "$json_file" "$client_file" "$links_file" "$raw_xray_dir" "$qr_dir" || true
        return 1
    fi
    if [[ -d "${stage_root}/qr" ]]; then
        if ! publish_staged_client_directory "${stage_root}/qr" "$qr_dir" "qr"; then
            restore_client_artifact_publish "$backup_root" "$json_file" "$client_file" "$links_file" "$raw_xray_dir" "$qr_dir" || true
            return 1
        fi
        log OK "QR-коды сохранены в ${qr_dir}"
    fi

    rm -rf -- "$backup_root" 2> /dev/null || true
    log OK "Конфигурации сохранены"
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
    local validate_rc=0
    save_client_configs_validate_prerequisites "$required_count" || validate_rc=$?
    if ((validate_rc == 2)); then
        return 0
    elif ((validate_rc != 0)); then
        return 1
    fi

    save_client_configs_write_server_keys "$keys_file" "$rule58" "$required_count"

    local json_configs='[]'
    # shellcheck disable=SC2034 # Used via nameref helper.
    local -a qr_links_v4=()
    # shellcheck disable=SC2034 # Used via nameref helper.
    local -a qr_links_v6=()
    local stage_root=""
    stage_root=$(client_artifacts_create_stage_dir) || return 1
    save_client_configs_build_inventory "$required_count" json_configs qr_links_v4 qr_links_v6 "${stage_root}/export" || {
        rm -rf -- "$stage_root"
        return 1
    }
    save_client_configs_stage_inventory_outputs "$stage_root" "$json_configs" qr_links_v4 qr_links_v6 || {
        rm -rf -- "$stage_root"
        return 1
    }
    save_client_configs_publish_staged_outputs "$stage_root" "$json_file" "$client_file" || {
        rm -rf -- "$stage_root"
        return 1
    }
    rm -rf -- "$stage_root"
}
