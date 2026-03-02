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
prepare_add_clients_runtime() {
    if [[ ! -x "$XRAY_BIN" ]]; then
        log ERROR "Xray не установлен. Сначала выполните: xray-reality.sh install"
        exit 1
    fi
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log ERROR "Конфигурация не найдена: ${XRAY_CONFIG}"
        exit 1
    fi

    if [[ -f "$XRAY_ENV" ]]; then
        load_config_file "$XRAY_ENV"
        apply_runtime_overrides
    fi

    if ! systemctl_available || ! systemd_running; then
        log ERROR "add-clients/add-keys требует systemd для безопасного перезапуска Xray"
        log ERROR "Сначала запустите окружение с рабочим systemd"
        exit 1
    fi

    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(fetch_ip 4 || echo "")
    fi
    if [[ -z "${SERVER_IP6:-}" ]]; then
        SERVER_IP6=$(fetch_ip 6 || echo "")
    fi
    if [[ -z "$SERVER_IP" ]] || ! is_valid_ipv4 "$SERVER_IP"; then
        log ERROR "Не удалось определить корректный IPv4 для add-clients/add-keys (SERVER_IP=${SERVER_IP:-empty})"
        exit 1
    fi
    if [[ -n "${SERVER_IP6:-}" ]] && ! is_valid_ipv6 "$SERVER_IP6"; then
        log WARN "Авто-детект вернул невалидный IPv6 для add-clients/add-keys: ${SERVER_IP6}. IPv6 ссылки будут пропущены."
        SERVER_IP6=""
    fi
}

resolve_add_clients_count() {
    local requested_count="$1"
    local out_existing_count_name="$2"
    local out_new_total_name="$3"

    local -n _out_existing_count="$out_existing_count_name"
    local -n _out_new_total="$out_new_total_name"

    load_existing_ports_from_config

    _out_existing_count=${#PORTS[@]}
    if ((_out_existing_count < 1)); then
        log ERROR "Не найдено существующих конфигураций в ${XRAY_CONFIG}"
        exit 1
    fi

    local max_total
    max_total=$(max_configs_for_tier "$DOMAIN_TIER")
    if ((_out_existing_count > max_total)); then
        log ERROR "Текущая конфигурация уже содержит ${_out_existing_count} профилей (лимит: ${max_total})"
        exit 1
    fi

    local max_add=$((max_total - _out_existing_count))
    if ((max_add < 1)); then
        log ERROR "Уже достигнут лимит: ${_out_existing_count}/${max_total}. Новые конфиги добавить нельзя."
        exit 1
    fi

    if [[ ! "$requested_count" =~ ^[0-9]+$ ]]; then
        log ERROR "Некорректное количество: ${requested_count}. Укажите число от 1 до ${max_add}."
        exit 1
    fi

    local has_tty=false
    if [[ -t 0 || -t 1 || -t 2 ]]; then
        has_tty=true
    fi

    if ((requested_count < 1)); then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log ERROR "Non-interactive режим: укажите количество add-clients/add-keys (1-${max_add})"
            exit 1
        fi
        if [[ "$has_tty" != "true" ]]; then
            log ERROR "Не удалось открыть /dev/tty для ввода количества новых конфигураций"
            exit 1
        fi
        local tty_fd=""
        if ! open_interactive_tty_fd tty_fd; then
            log ERROR "Не удалось открыть /dev/tty для ввода количества новых конфигураций"
            exit 1
        fi
        printf '\n' >&"$tty_fd"
        local input
        while true; do
            if ! printf "Количество VPN-ключей добавить (1-%s): " "$max_add" >&"$tty_fd"; then
                exec {tty_fd}>&-
                log ERROR "Не удалось вывести запрос количества новых конфигураций в /dev/tty"
                exit 1
            fi
            if ! read -r -u "$tty_fd" input; then
                exec {tty_fd}>&-
                log ERROR "Не удалось прочитать количество новых конфигураций из /dev/tty"
                exit 1
            fi
            input=$(normalize_tty_input "$input")
            if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= max_add)); then
                requested_count="$input"
                break
            fi
            printf '%bВведите число от 1 до %s%b\n' "$RED" "$max_add" "$NC" >&"$tty_fd"
        done
        exec {tty_fd}>&-
    fi

    if ((requested_count > max_add)); then
        log ERROR "Превышение лимита: текущих ${_out_existing_count}, добавить можно максимум ${max_add}, запрошено ${requested_count}"
        exit 1
    fi

    _out_new_total=$((_out_existing_count + requested_count))
    if ((_out_new_total > max_total)); then
        log ERROR "Превышение лимита конфигураций: ${_out_new_total}/${max_total}"
        exit 1
    fi

    ADD_CLIENTS_COUNT="$requested_count"
    log INFO "Добавление ${requested_count} новых конфигураций (текущих: ${_out_existing_count}, итого: ${_out_new_total})"
}

allocate_additional_client_ports() {
    local add_count="$1"
    local out_ports_name="$2"
    local out_ports_v6_name="$3"

    local -n _out_ports="$out_ports_name"
    local -n _out_ports_v6="$out_ports_v6_name"
    _out_ports=()
    _out_ports_v6=()

    local all_allocated=""
    local p
    for p in "${PORTS[@]}"; do
        all_allocated="$all_allocated $p"
    done
    if [[ "$HAS_IPV6" == true ]]; then
        for p in "${PORTS_V6[@]}"; do
            all_allocated="$all_allocated $p"
        done
    fi

    local max_port=0
    for p in "${PORTS[@]}"; do
        ((p > max_port)) && max_port=$p
    done
    local next_port=$((max_port + 1))

    local i
    for ((i = 0; i < add_count; i++)); do
        local port
        port=$(find_free_port "$next_port" "$all_allocated") || {
            log ERROR "Нет доступных портов для IPv4"
            exit 1
        }
        _out_ports+=("$port")
        all_allocated="$all_allocated $port"
        next_port=$((port + 1))

        if [[ "$HAS_IPV6" == true ]]; then
            local v6_start
            if ((port < 4535)); then
                v6_start=$((port + 61000))
                if ((v6_start > 65535)); then
                    v6_start=61000
                fi
            else
                v6_start=$((port + 10000))
                if ((v6_start > 65535)); then
                    v6_start=$((61000 + (port % 4535)))
                fi
            fi
            local v6_port=""
            if ! v6_port=$(find_free_port "$v6_start" "$all_allocated"); then
                log WARN "Не удалось выделить IPv6 порт для конфига $((i + 1))"
                _out_ports_v6+=("")
            else
                _out_ports_v6+=("$v6_port")
                all_allocated="$all_allocated $v6_port"
            fi
        fi
    done
}

generate_additional_client_keys() {
    local add_count="$1"
    local out_private_name="$2"
    local out_public_name="$3"
    local out_uuids_name="$4"
    local out_short_ids_name="$5"

    local -n _out_private="$out_private_name"
    local -n _out_public="$out_public_name"
    local -n _out_uuids="$out_uuids_name"
    local -n _out_short_ids="$out_short_ids_name"
    _out_private=()
    _out_public=()
    _out_uuids=()
    _out_short_ids=()

    log STEP "Генерируем ключи для новых конфигураций..."
    local i
    for ((i = 0; i < add_count; i++)); do
        local pair priv pub
        pair=$(generate_x25519_keypair) || return 1
        IFS=$'\t' read -r priv pub <<< "$pair"
        _out_private+=("$priv")
        _out_public+=("$pub")
        local new_uuid
        new_uuid=$(generate_uuid) || {
            log ERROR "Не удалось сгенерировать UUID для нового конфига"
            return 1
        }
        _out_uuids+=("$new_uuid")
        _out_short_ids+=("$(generate_short_id)")
    done
    log OK "Ключи сгенерированы (${add_count} шт.)"
}

build_add_clients_inbounds() {
    local add_count="$1"
    local existing_count="$2"
    local new_ports_name="$3"
    local new_ports_v6_name="$4"
    local new_private_keys_name="$5"
    local new_uuids_name="$6"
    local new_short_ids_name="$7"
    local out_inbounds_name="$8"
    local out_domains_name="$9"
    local out_snis_name="${10}"
    local out_grpc_name="${11}"
    local out_fps_name="${12}"

    local -n _new_ports="$new_ports_name"
    local -n _new_ports_v6="$new_ports_v6_name"
    local -n _new_private_keys="$new_private_keys_name"
    local -n _new_uuids="$new_uuids_name"
    local -n _new_short_ids="$new_short_ids_name"
    local -n _out_domains="$out_domains_name"
    local -n _out_snis="$out_snis_name"
    local -n _out_grpc="$out_grpc_name"
    local -n _out_fps="$out_fps_name"
    _out_domains=()
    _out_snis=()
    _out_grpc=()
    _out_fps=()

    if ! build_domain_plan "$add_count" "false"; then
        log ERROR "Не удалось сформировать доменный план для add-clients"
        return 1
    fi

    # shellcheck disable=SC2034 # Used via nameref in pick_random_from_array.
    local -a fp_pool=("chrome" "chrome" "chrome" "firefox" "chrome" "firefox")
    local tmp_inbounds
    if ! tmp_inbounds=$(mktemp "${TMPDIR:-/tmp}/xray-add-inbounds.XXXXXX"); then
        log ERROR "Не удалось создать временный файл для add-clients inbounds"
        return 1
    fi

    local i
    for ((i = 0; i < add_count; i++)); do
        local domain="${DOMAIN_SELECTION_PLAN[$i]:-${AVAILABLE_DOMAINS[0]}}"
        build_inbound_profile_for_domain "$domain" fp_pool
        _out_domains+=("$domain")
        _out_snis+=("$PROFILE_SNI")
        _out_grpc+=("$PROFILE_GRPC")
        _out_fps+=("$PROFILE_FP")

        local config_num=$((existing_count + i + 1))
        local sni_count
        sni_count=$(echo "$PROFILE_SNI_JSON" | jq 'length' 2> /dev/null || echo 1)
        log INFO "Config ${config_num}: ${domain} -> ${PROFILE_DEST} (${PROFILE_FP}, ${TRANSPORT}, SNIs: ${sni_count})"

        local inbound_v4
        if ! inbound_v4=$(generate_profile_inbound_json \
            "${_new_ports[$i]}" "${_new_uuids[$i]}" "${_new_private_keys[$i]}" "${_new_short_ids[$i]}"); then
            rm -f "$tmp_inbounds"
            log ERROR "Ошибка генерации IPv4 inbound для add-clients config #${config_num}"
            return 1
        fi
        printf '%s\n' "$inbound_v4" >> "$tmp_inbounds"

        if [[ "$HAS_IPV6" == true && -n "${_new_ports_v6[$i]:-}" ]]; then
            local inbound_v6
            if ! inbound_v6=$(echo "$inbound_v4" | jq --arg port "${_new_ports_v6[$i]}" '.listen = "::" | .port = ($port|tonumber)' 2> /dev/null); then
                rm -f "$tmp_inbounds"
                log ERROR "Ошибка генерации IPv6 inbound для add-clients config #${config_num} (port=${_new_ports_v6[$i]})"
                return 1
            fi
            printf '%s\n' "$inbound_v6" >> "$tmp_inbounds"
        fi
    done

    local inbounds_payload='[]'
    if [[ -s "$tmp_inbounds" ]]; then
        if ! inbounds_payload=$(jq -s '.' "$tmp_inbounds" 2> /dev/null); then
            rm -f "$tmp_inbounds"
            log ERROR "Ошибка сборки add-clients inbounds payload"
            return 1
        fi
    fi
    rm -f "$tmp_inbounds"
    printf -v "$out_inbounds_name" '%s' "$inbounds_payload"
}

append_add_clients_keys_file() {
    local existing_count="$1"
    local add_count="$2"
    local rule58="$3"
    local new_private_keys_name="$4"
    local new_public_keys_name="$5"
    local new_uuids_name="$6"
    local new_short_ids_name="$7"
    local new_ports_name="$8"
    local new_ports_v6_name="$9"

    local -n _new_private_keys="$new_private_keys_name"
    local -n _new_public_keys="$new_public_keys_name"
    local -n _new_uuids="$new_uuids_name"
    local -n _new_short_ids="$new_short_ids_name"
    local -n _new_ports="$new_ports_name"
    local -n _new_ports_v6="$new_ports_v6_name"

    local keys_file="${XRAY_KEYS}/keys.txt"
    [[ -f "$keys_file" ]] || return 0

    backup_file "$keys_file"
    local tmp_keys
    tmp_keys=$(mktemp "${keys_file}.tmp.XXXXXX")
    cp -a "$keys_file" "$tmp_keys"

    local i
    for ((i = 0; i < add_count; i++)); do
        local config_num=$((existing_count + i + 1))
        cat >> "$tmp_keys" << EOF
${rule58}
Config ${config_num}:
${rule58}
Private Key: ${_new_private_keys[$i]}
Public Key:  ${_new_public_keys[$i]}
UUID:        ${_new_uuids[$i]}
ShortID:     ${_new_short_ids[$i]}
Port IPv4:   ${_new_ports[$i]}
Port IPv6:   ${_new_ports_v6[$i]:-N/A}

EOF
    done

    mv "$tmp_keys" "$keys_file"
    chmod 400 "$keys_file"
    chown root:root "$keys_file"
}

build_add_clients_links() {
    local existing_count="$1"
    local add_count="$2"
    local add_domains_name="$3"
    local add_snis_name="$4"
    local add_fps_name="$5"
    local add_grpc_name="$6"
    local new_public_keys_name="$7"
    local new_short_ids_name="$8"
    local new_uuids_name="$9"
    local new_ports_name="${10}"
    local new_ports_v6_name="${11}"
    local out_vless_v4_name="${12}"
    local out_vless_v6_name="${13}"

    local -n _add_domains="$add_domains_name"
    local -n _add_snis="$add_snis_name"
    local -n _add_fps="$add_fps_name"
    local -n _add_grpc="$add_grpc_name"
    local -n _new_public_keys="$new_public_keys_name"
    local -n _new_short_ids="$new_short_ids_name"
    local -n _new_uuids="$new_uuids_name"
    local -n _new_ports="$new_ports_name"
    local -n _new_ports_v6="$new_ports_v6_name"
    local -n _out_vless_v4="$out_vless_v4_name"
    local -n _out_vless_v6="$out_vless_v6_name"
    _out_vless_v4=()
    _out_vless_v6=()

    local i
    local link_prefix
    link_prefix=$(client_link_prefix_for_tier "$DOMAIN_TIER")
    for ((i = 0; i < add_count; i++)); do
        local config_num=$((existing_count + i + 1))
        local domain="${_add_domains[$i]}"
        local sni="${_add_snis[$i]}"
        local fp="${_add_fps[$i]}"
        local grpc="${_add_grpc[$i]}"
        local clean_name endpoint params

        clean_name=$(echo "$domain" | sed 's/www\.//; s/\./-/g')
        endpoint="$grpc"
        if [[ "$TRANSPORT" == "http2" ]]; then
            endpoint=$(grpc_service_to_http2_path "$grpc")
        fi
        params=$(build_vless_query_params "$sni" "$fp" "${_new_public_keys[$i]}" "${_new_short_ids[$i]}" "$TRANSPORT" "$endpoint")
        _out_vless_v4+=("vless://${_new_uuids[$i]}@${SERVER_IP}:${_new_ports[$i]}?${params}#${link_prefix}-${clean_name}-${config_num}")

        if [[ "$HAS_IPV6" == true && -n "${SERVER_IP6:-}" && -n "${_new_ports_v6[$i]:-}" ]]; then
            _out_vless_v6+=("vless://${_new_uuids[$i]}@[${SERVER_IP6}]:${_new_ports_v6[$i]}?${params}#${link_prefix}-${clean_name}-v6-${config_num}")
        else
            _out_vless_v6+=("")
        fi
    done
}

append_add_clients_json() {
    local existing_count="$1"
    local add_count="$2"
    local add_domains_name="$3"
    local add_snis_name="$4"
    local add_fps_name="$5"
    local add_grpc_name="$6"
    local new_uuids_name="$7"
    local new_short_ids_name="$8"
    local new_public_keys_name="$9"
    local new_ports_name="${10}"
    local new_ports_v6_name="${11}"
    local new_vless_v4_name="${12}"
    local new_vless_v6_name="${13}"
    local client_file="${14}"

    local -n _add_domains="$add_domains_name"
    local -n _add_snis="$add_snis_name"
    local -n _add_fps="$add_fps_name"
    local -n _add_grpc="$add_grpc_name"
    local -n _new_uuids="$new_uuids_name"
    local -n _new_short_ids="$new_short_ids_name"
    local -n _new_public_keys="$new_public_keys_name"
    local -n _new_ports="$new_ports_name"
    local -n _new_ports_v6="$new_ports_v6_name"
    local -n _new_vless_v4="$new_vless_v4_name"
    local -n _new_vless_v6="$new_vless_v6_name"

    local json_file="${XRAY_KEYS}/clients.json"
    if [[ ! -f "$json_file" ]]; then
        log WARN "Файл clients.json не найден; пересобираем клиентские артефакты из текущей конфигурации"
        save_client_configs
        return 0
    fi

    backup_file "$json_file"
    validate_clients_json_file "$json_file" || return 1

    local profiles_tmp
    profiles_tmp=$(mktemp "${TMPDIR:-/tmp}/xray-add-profiles.XXXXXX")
    local i
    for ((i = 0; i < add_count; i++)); do
        local config_num=$((existing_count + i + 1))
        local json_transport_endpoint="${_add_grpc[$i]}"
        if [[ "$TRANSPORT" == "http2" ]]; then
            json_transport_endpoint=$(grpc_service_to_http2_path "$json_transport_endpoint")
        fi

        jq -n \
            --arg name "Config ${config_num}" \
            --arg domain "${_add_domains[$i]}" \
            --arg sni "${_add_snis[$i]}" \
            --arg fp "${_add_fps[$i]}" \
            --arg grpc "$json_transport_endpoint" \
            --arg transport "$TRANSPORT" \
            --arg uuid "${_new_uuids[$i]}" \
            --arg short_id "${_new_short_ids[$i]}" \
            --arg public_key "${_new_public_keys[$i]}" \
            --arg port_ipv4 "${_new_ports[$i]}" \
            --arg port_ipv6 "${_new_ports_v6[$i]:-}" \
            --arg vless_v4 "${_new_vless_v4[$i]}" \
            --arg vless_v6 "${_new_vless_v6[$i]:-}" \
            '{
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
                port_ipv4: ($port_ipv4 | tonumber),
                port_ipv6: (if ($port_ipv6 | length) > 0 then ($port_ipv6 | tonumber?) else null end),
                vless_v4: $vless_v4,
                vless_v6: (if ($vless_v6 | length) > 0 then $vless_v6 else null end)
            }' >> "$profiles_tmp"
    done

    local new_json_configs='[]'
    if [[ -s "$profiles_tmp" ]]; then
        new_json_configs=$(jq -s '.' "$profiles_tmp")
    fi
    rm -f "$profiles_tmp"

    local tmp_json
    tmp_json=$(mktemp "${json_file}.tmp.XXXXXX")
    jq --argjson new "$new_json_configs" '.configs += $new' "$json_file" > "$tmp_json"
    mv "$tmp_json" "$json_file"
    secure_clients_json_permissions "$json_file"
    render_clients_txt_from_json "$json_file" "$client_file"
}

add_clients_generate_qr() {
    local existing_count="$1"
    local add_count="$2"
    local new_vless_v4_name="$3"
    local new_vless_v6_name="$4"
    local -n _new_vless_v4="$new_vless_v4_name"
    local -n _new_vless_v6="$new_vless_v6_name"

    if [[ "$QR_ENABLED" == "false" ]] || ! command -v qrencode > /dev/null 2>&1; then
        return 0
    fi

    local qr_dir="${XRAY_KEYS}/qr"
    mkdir -p "$qr_dir"
    local i
    for ((i = 0; i < add_count; i++)); do
        local idx=$((existing_count + i))
        if [[ -n "${_new_vless_v4[$i]:-}" ]]; then
            qrencode -o "${qr_dir}/config-${idx}-v4.png" -s 6 -m 2 "${_new_vless_v4[$i]}" > /dev/null 2>&1 || true
        fi
        if [[ -n "${_new_vless_v6[$i]:-}" ]]; then
            qrencode -o "${qr_dir}/config-${idx}-v6.png" -s 6 -m 2 "${_new_vless_v6[$i]}" > /dev/null 2>&1 || true
        fi
    done
}

restart_and_verify_add_clients_ports() {
    local new_ports_name="$1"
    local -n _new_ports="$new_ports_name"

    log STEP "Перезапускаем Xray..."
    if ! declare -F systemctl_restart_xray_bounded > /dev/null; then
        log ERROR "Не найден helper systemctl_restart_xray_bounded для безопасного restart"
        return 1
    fi
    if ! systemctl_restart_xray_bounded; then
        log ERROR "Не удалось перезапустить Xray"
        return 1
    fi

    sleep 2
    if ! systemctl is-active --quiet xray; then
        log ERROR "Xray не запустился после обновления конфигурации"
        log ERROR "Проверьте: journalctl -u xray -n 20"
        return 1
    fi
    log OK "Xray перезапущен"

    local listening_new expected_new
    read -r listening_new expected_new < <(count_listening_ports "${_new_ports[@]}")
    local port
    for port in "${_new_ports[@]}"; do
        [[ -n "$port" ]] || continue
        if ! port_is_listening "$port"; then
            log WARN "Новый порт не слушается: ${port}"
        fi
    done
    if ((expected_new < 1)); then
        log ERROR "Не найдено новых портов для проверки после add-clients"
        return 1
    fi
    if ((listening_new != expected_new)); then
        if ((listening_new == 0)); then
            log ERROR "После перезапуска ни один новый порт не слушается"
        else
            log ERROR "После перезапуска слушается только ${listening_new}/${expected_new} новых IPv4 портов"
        fi
        return 1
    fi
}

print_add_clients_result() {
    local add_count="$1"
    local existing_count="$2"
    local client_file="$3"
    local new_vless_v4_name="$4"
    local new_vless_v6_name="$5"
    local -n _new_vless_v4="$new_vless_v4_name"
    local -n _new_vless_v6="$new_vless_v6_name"

    echo ""
    local title="ДОБАВЛЕНО ${add_count} НОВЫХ КОНФИГУРАЦИЙ"
    local box_width box_top box_line box_bottom
    box_width=$(ui_box_width_for_lines 60 90 "$title")
    box_top=$(ui_box_border_string top "$box_width")
    box_line=$(ui_box_line_string "$title" "$box_width")
    box_bottom=$(ui_box_border_string bottom "$box_width")
    echo -e "${BOLD}${GREEN}${box_top}${NC}"
    echo -e "${BOLD}${GREEN}${box_line}${NC}"
    echo -e "${BOLD}${GREEN}${box_bottom}${NC}"
    echo ""

    if ! can_write_dev_tty; then
        log INFO "Терминал недоступен; новые ссылки не печатаются в лог. Откройте файл: ${client_file}"
        echo -e "📁 Обновлено: ${client_file}"
        echo ""
        return 0
    fi

    local tty_write_ok=true
    local i
    for ((i = 0; i < add_count; i++)); do
        local config_num=$((existing_count + i + 1))
        if ! {
            echo -e "${BOLD}$(ui_section_title_string "Конфиг #${config_num}")${NC}"
            echo "${_new_vless_v4[$i]}"
            if [[ -n "${_new_vless_v6[$i]:-}" ]]; then
                echo "${_new_vless_v6[$i]}"
            fi
            echo ""
        } > /dev/tty 2> /dev/null; then
            tty_write_ok=false
            break
        fi
    done

    if [[ "$tty_write_ok" == true ]]; then
        if ! {
            echo -e "📁 Обновлено: ${client_file}"
            echo ""
        } > /dev/tty 2> /dev/null; then
            tty_write_ok=false
        fi
    fi

    if [[ "$tty_write_ok" == true ]]; then
        log INFO "Новые клиентские ссылки выведены только в /dev/tty (в install log не записаны)"
    else
        log INFO "Терминал недоступен; новые ссылки не печатаются в лог. Откройте файл: ${client_file}"
        echo -e "📁 Обновлено: ${client_file}"
        echo ""
    fi
}

add_clients_flow() {
    local add_count="${ADD_CLIENTS_COUNT:-0}"
    local rule58
    rule58="$(ui_rule_string 58)"

    LOG_CONTEXT="добавления клиентов"
    : "${LOG_CONTEXT}"
    setup_logging
    prepare_add_clients_runtime

    local existing_count=0
    local new_total=0
    resolve_add_clients_count "$add_count" existing_count new_total
    add_count="${ADD_CLIENTS_COUNT}"

    validate_install_config
    setup_domains

    local -a new_ports=()
    local -a new_ports_v6=()
    allocate_additional_client_ports "$add_count" new_ports new_ports_v6
    log OK "Выделены порты: ${new_ports[*]}"

    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_private_keys=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_public_keys=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_uuids=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_short_ids=()
    generate_additional_client_keys "$add_count" new_private_keys new_public_keys new_uuids new_short_ids || exit 1

    log STEP "Обновляем конфигурацию Xray..."
    setup_mux_settings

    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a add_domains=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a add_snis=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a add_grpc_services=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a add_fps=()
    local new_inbounds='[]'
    build_add_clients_inbounds \
        "$add_count" \
        "$existing_count" \
        new_ports \
        new_ports_v6 \
        new_private_keys \
        new_uuids \
        new_short_ids \
        new_inbounds \
        add_domains \
        add_snis \
        add_grpc_services \
        add_fps || exit 1

    backup_file "$XRAY_CONFIG"
    local tmp_config
    tmp_config=$(create_temp_xray_config_file)
    jq --argjson new "$new_inbounds" '.inbounds += $new' "$XRAY_CONFIG" > "$tmp_config"
    set_temp_xray_config_permissions "$tmp_config"
    apply_validated_config "$tmp_config" || exit 1
    log OK "Конфигурация обновлена"

    log STEP "Обновляем файрвол..."
    local -a fw_ports=("${new_ports[@]}")
    if [[ "$HAS_IPV6" == true ]]; then
        fw_ports+=("${new_ports_v6[@]}")
    fi
    local fw_status
    fw_status=$(open_firewall_ports "${new_ports[*]}" "${new_ports_v6[*]}")
    case "$fw_status" in
        ok) log OK "Файрвол обновлён" ;;
        partial) log WARN "Файрвол обновлён частично — проверьте правила" ;;
        *)
            log INFO "Автоматическая настройка файрвола пропущена"
            log INFO "Откройте порты вручную: ${fw_ports[*]}"
            ;;
    esac

    append_add_clients_keys_file \
        "$existing_count" \
        "$add_count" \
        "$rule58" \
        new_private_keys \
        new_public_keys \
        new_uuids \
        new_short_ids \
        new_ports \
        new_ports_v6

    local client_file="${XRAY_KEYS}/clients.txt"
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_vless_v4=()
    # shellcheck disable=SC2034 # Passed to helper functions via nameref.
    local -a new_vless_v6=()
    build_add_clients_links \
        "$existing_count" \
        "$add_count" \
        add_domains \
        add_snis \
        add_fps \
        add_grpc_services \
        new_public_keys \
        new_short_ids \
        new_uuids \
        new_ports \
        new_ports_v6 \
        new_vless_v4 \
        new_vless_v6

    append_add_clients_json \
        "$existing_count" \
        "$add_count" \
        add_domains \
        add_snis \
        add_fps \
        add_grpc_services \
        new_uuids \
        new_short_ids \
        new_public_keys \
        new_ports \
        new_ports_v6 \
        new_vless_v4 \
        new_vless_v6 \
        "$client_file" || exit 1

    add_clients_generate_qr "$existing_count" "$add_count" new_vless_v4 new_vless_v6
    if [[ -f "$XRAY_ENV" ]]; then
        update_env_num_configs "$XRAY_ENV" "$new_total" || log WARN "Не удалось обновить NUM_CONFIGS в $XRAY_ENV"
    fi

    restart_and_verify_add_clients_ports new_ports || exit 1
    if client_artifacts_missing || client_artifacts_inconsistent "$new_total"; then
        log WARN "Обнаружены отсутствующие или рассинхронизированные клиентские артефакты; выполняем полную пересборку"
        rebuild_client_artifacts_from_config || {
            log ERROR "Не удалось пересобрать клиентские артефакты"
            exit 1
        }
    fi

    print_add_clients_result "$add_count" "$existing_count" "$client_file" new_vless_v4 new_vless_v6
}

verify_ports_listening_after_start() {
    if ! systemctl_available || ! systemd_running; then
        log WARN "systemd недоступен; проверка listening-портов после запуска пропущена"
        return 0
    fi

    local attempts=0
    local max_attempts=10
    local listening_v4=0
    local expected_v4=0
    local port

    for port in "${PORTS[@]}"; do
        [[ -n "$port" ]] || continue
        expected_v4=$((expected_v4 + 1))
    done
    if ((expected_v4 < 1)); then
        log ERROR "Нет IPv4 портов для проверки после запуска"
        return 1
    fi

    while ((attempts < max_attempts)); do
        listening_v4=0
        for port in "${PORTS[@]}"; do
            [[ -n "$port" ]] || continue
            if port_is_listening "$port"; then
                listening_v4=$((listening_v4 + 1))
            fi
        done
        if ((listening_v4 == expected_v4)); then
            return 0
        fi
        sleep 1
        ((attempts += 1))
    done

    for port in "${PORTS[@]}"; do
        [[ -n "$port" ]] || continue
        if ! port_is_listening "$port"; then
            log WARN "Порт не слушается после запуска: ${port}"
        fi
    done

    if [[ "$HAS_IPV6" == true ]]; then
        for port in "${PORTS_V6[@]}"; do
            [[ -n "$port" ]] || continue
            if ! port_is_listening "$port"; then
                log WARN "IPv6 порт не слушается после запуска: ${port}"
            fi
        done
    fi

    if ((listening_v4 == 0)); then
        log ERROR "После запуска Xray ни один IPv4 порт не слушается"
        if systemctl_available && systemd_running; then
            log INFO "systemd: status xray"
            systemctl status xray --no-pager -l 2> /dev/null || true
            log INFO "journal: xray (last 80 lines)"
            journalctl -u xray -n 80 --no-pager 2> /dev/null || true
        fi
        if [[ -f "$XRAY_CONFIG" ]] && command -v jq > /dev/null 2>&1; then
            log INFO "ожидаемые inbounds (port listen protocol network)"
            jq -r '
                .inbounds[]
                | select(.port != null)
                | [(.port|tostring), (.listen // "0.0.0.0"), (.protocol // "?"), (.streamSettings.network // "?")]
                | @tsv
            ' "$XRAY_CONFIG" 2> /dev/null || true
        fi
        return 1
    fi

    log ERROR "После запуска слушается только ${listening_v4}/${expected_v4} IPv4 портов"
    return 1
}
