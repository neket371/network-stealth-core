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

SELF_CHECK_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/health/self_check.sh"
if [[ ! -f "$SELF_CHECK_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    SELF_CHECK_MODULE="$XRAY_DATA_DIR/modules/health/self_check.sh"
fi
if [[ -f "$SELF_CHECK_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$SELF_CHECK_MODULE"
fi

OPERATOR_DECISION_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/health/operator_decision.sh"
if [[ ! -f "$OPERATOR_DECISION_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    OPERATOR_DECISION_MODULE="$XRAY_DATA_DIR/modules/health/operator_decision.sh"
fi
if [[ -f "$OPERATOR_DECISION_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$OPERATOR_DECISION_MODULE"
fi

CONFIG_SHARED_HELPERS_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SHARED_HELPERS_MODULE"
fi

SERVICE_UNINSTALL_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/service/uninstall.sh"
if [[ ! -f "$SERVICE_UNINSTALL_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    SERVICE_UNINSTALL_MODULE="$XRAY_DATA_DIR/modules/service/uninstall.sh"
fi
if [[ ! -f "$SERVICE_UNINSTALL_MODULE" ]]; then
    log ERROR "Не найден модуль service uninstall: $SERVICE_UNINSTALL_MODULE"
    exit 1
fi
# shellcheck source=modules/service/uninstall.sh
source "$SERVICE_UNINSTALL_MODULE"

SERVICE_RUNTIME_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/service/runtime.sh"
if [[ ! -f "$SERVICE_RUNTIME_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    SERVICE_RUNTIME_MODULE="$XRAY_DATA_DIR/modules/service/runtime.sh"
fi
if [[ ! -f "$SERVICE_RUNTIME_MODULE" ]]; then
    log ERROR "Не найден модуль service runtime: $SERVICE_RUNTIME_MODULE"
    exit 1
fi
# shellcheck source=modules/service/runtime.sh
source "$SERVICE_RUNTIME_MODULE"

assign_latest_backup_dir() {
    local out_name="$1"
    local latest=""
    if [[ -d "$XRAY_BACKUP" ]]; then
        while IFS= read -r latest; do
            break
        done < <(find "$XRAY_BACKUP" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' |
            sort -nr |
            cut -f2-)
    fi
    printf -v "$out_name" '%s' "$latest"
    [[ -n "$latest" ]]
}

rollback_from_session() {
    local session_dir="$1"
    if [[ -z "$session_dir" ]]; then
        assign_latest_backup_dir session_dir || true
    fi
    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        log ERROR "Бэкапы не найдены в $XRAY_BACKUP"
        exit 1
    fi

    log STEP "Откат из бэкапа: $session_dir"

    local -a safe_restore_prefixes=()
    local safe_seen="|"
    local candidate resolved_candidate
    for candidate in \
        "/etc/systemd" \
        "/etc/logrotate.d" \
        "$(dirname "$XRAY_CONFIG")" \
        "$(dirname "$XRAY_ENV")" \
        "$XRAY_KEYS" \
        "$XRAY_LOGS" \
        "$XRAY_HOME" \
        "$XRAY_DATA_DIR" \
        "$(dirname "$XRAY_BIN")" \
        "$(dirname "$XRAY_SCRIPT_PATH")" \
        "$(dirname "$XRAY_UPDATE_SCRIPT")" \
        "$(dirname "$MINISIGN_KEY")" \
        "$(xray_geo_dir)"; do
        [[ -n "$candidate" ]] || continue
        resolved_candidate=$(realpath -m "$candidate" 2> /dev/null || echo "$candidate")
        [[ "$resolved_candidate" == /* ]] || continue
        if is_dangerous_destructive_path "$resolved_candidate"; then
            continue
        fi
        if [[ "$safe_seen" == *"|${resolved_candidate}|"* ]]; then
            continue
        fi
        safe_seen+="${resolved_candidate}|"
        safe_restore_prefixes+=("$resolved_candidate")
    done

    local resolved_session
    resolved_session=$(realpath "$session_dir" 2> /dev/null) || resolved_session="$session_dir"
    local resolved_backup
    resolved_backup=$(realpath "$XRAY_BACKUP" 2> /dev/null) || resolved_backup="$XRAY_BACKUP"
    if [[ "$resolved_session" != "$resolved_backup"/* ]]; then
        log ERROR "Бэкап вне разрешённой директории: $session_dir"
        exit 1
    fi

    if declare -F runtime_quiesce_for_restore > /dev/null 2>&1; then
        runtime_quiesce_for_restore || true
    fi

    (
        cd "$session_dir" || exit 1
        while IFS= read -r -d '' file; do
            local rel="${file#./}"
            local dest="/${rel}"

            local resolved_dest
            resolved_dest=$(realpath -m "$dest" 2> /dev/null) || resolved_dest="$dest"
            if [[ "$resolved_dest" == *".."* ]]; then
                log WARN "Пропускаем путь с ..: $dest"
                continue
            fi

            local is_safe=false
            for prefix in "${safe_restore_prefixes[@]}"; do
                if [[ "$resolved_dest" == "$prefix" || "$resolved_dest" == "$prefix"/* ]]; then
                    is_safe=true
                    break
                fi
            done

            if [[ "$is_safe" != true ]]; then
                log WARN "Пропускаем небезопасный путь: $dest"
                continue
            fi

            if declare -F restore_file_from_snapshot > /dev/null 2>&1; then
                restore_file_from_snapshot "$session_dir/$rel" "$dest" || {
                    log ERROR "Не удалось восстановить: $dest"
                    exit 1
                }
            else
                mkdir -p "$(dirname "$dest")"
                cp -a "$session_dir/$rel" "$dest" || {
                    log ERROR "Не удалось восстановить: $dest"
                    exit 1
                }
            fi
            log INFO "Восстановлен: $dest"
        done < <(find . \( -type f -o -type l \) -print0)
    )

    if declare -F reconcile_runtime_after_restore > /dev/null 2>&1; then
        reconcile_runtime_after_restore || true
    elif ! systemd_running; then
        log WARN "systemd не запущен; перезапуск сервисов пропущен"
    fi

    log OK "Откат завершён"
}

status_flow_render_header() {
    local status_title status_box_width
    status_title="NETWORK STEALTH CORE - STATUS"
    status_box_width=$(ui_box_width_for_lines 60 90 "$status_title")
    echo ""
    echo -e "${BOLD}${CYAN}$(ui_box_border_string top "$status_box_width")${NC}"
    echo -e "${BOLD}${CYAN}$(ui_box_line_string "$status_title" "$status_box_width")${NC}"
    echo -e "${BOLD}${CYAN}$(ui_box_border_string bottom "$status_box_width")${NC}"
    echo ""
}

status_flow_render_runtime() {
    echo -e "${BOLD}Xray:${NC}"
    if systemctl is-active --quiet xray 2> /dev/null; then
        local xray_uptime
        xray_uptime=$(systemctl show xray --property=ActiveEnterTimestamp --value 2> /dev/null || echo "unknown")
        echo -e "  Статус: ${GREEN}активен${NC}"
        echo -e "  Запущен: ${xray_uptime}"
        if [[ -x "$XRAY_BIN" ]]; then
            local version
            version=$("$XRAY_BIN" version 2> /dev/null | head -1 | awk '{print $2}' || echo "unknown")
            echo -e "  Версия: ${version}"
        fi
    else
        echo -e "  Статус: ${RED}не запущен${NC}"
    fi
    echo ""
}

status_flow_render_config_summary() {
    [[ -f "$XRAY_CONFIG" ]] || return 0

    echo -e "${BOLD}Конфигурация:${NC}"
    local num_inbounds
    num_inbounds=$(jq '.inbounds | length' "$XRAY_CONFIG" 2> /dev/null || echo "?")
    echo -e "  Inbounds: ${num_inbounds}"

    local transport_mode
    transport_mode=$(jq -r '
        .inbounds[]
        | select(.streamSettings.realitySettings != null)
        | select((.listen // "0.0.0.0") | test(":") | not)
        | .streamSettings.network // "xhttp"
        ' "$XRAY_CONFIG" 2> /dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')
    transport_normalize_assign transport_mode "$transport_mode"
    case "$transport_mode" in
        grpc | http2 | xhttp) ;;
        *) transport_mode="unknown" ;;
    esac
    echo -e "  Transport: ${transport_mode}"
    if transport_is_legacy "$transport_mode"; then
        echo -e "  Режим: legacy transport (рекомендуется xray-reality.sh migrate-stealth)"
    elif [[ "$transport_mode" == "unknown" ]]; then
        echo -e "  Режим: ${YELLOW}нераспознанный транспорт${NC}"
    fi
    if [[ "$(normalize_domain_tier "${DOMAIN_TIER:-${DOMAIN_PROFILE:-tier_ru}}" 2> /dev/null || echo "")" == "custom" ]]; then
        if [[ -n "${XRAY_DOMAINS_FILE:-}" ]]; then
            echo -e "  Источник доменов: managed custom list (${XRAY_DOMAINS_FILE})"
        else
            echo -e "  Источник доменов: ${YELLOW}custom profile без managed source${NC}"
        fi
    fi

    local ports
    ports=$(jq -r '.inbounds[] | select(.listen == "0.0.0.0" or .listen == null) | .port' "$XRAY_CONFIG" 2> /dev/null | tr '\n' ' ')
    if [[ -n "$ports" ]]; then
        echo -e "  Порты IPv4: ${ports}"
    fi

    local ports_v6
    ports_v6=$(jq -r '.inbounds[] | select(.listen == "::") | .port' "$XRAY_CONFIG" 2> /dev/null | tr '\n' ' ')
    if [[ -n "$ports_v6" ]]; then
        echo -e "  Порты IPv6: ${ports_v6}"
    fi

    local domains
    domains=$(jq -r '.inbounds[] | select(.listen == "0.0.0.0" or .listen == null) | .streamSettings.realitySettings.dest // empty' "$XRAY_CONFIG" 2> /dev/null | sed 's/:.*//' | sort -u | tr '\n' ' ')
    if [[ -n "$domains" ]]; then
        echo -e "  Домены: ${domains}"
    fi
    echo ""
}

status_flow_render_server_info() {
    echo -e "${BOLD}Сервер:${NC}"
    local server_ip="${SERVER_IP:-}"
    [[ -n "$server_ip" ]] || server_ip="недоступен (не задан в config.env)"
    echo -e "  IPv4: ${server_ip}"
    local server_ip6="${SERVER_IP6:-}"
    [[ -n "$server_ip6" ]] || server_ip6="недоступен"
    echo -e "  IPv6: ${server_ip6}"
    echo ""
}

status_flow_render_client_artifacts() {
    if [[ -d "$XRAY_KEYS" ]]; then
        echo -e "${BOLD}Клиентские конфиги:${NC}"
        echo -e "  ${XRAY_KEYS}/clients.txt"
        if [[ -f "${XRAY_KEYS}/clients-links.txt" ]]; then
            echo -e "  ${XRAY_KEYS}/clients-links.txt"
        fi
        if [[ -d "${XRAY_KEYS}/export" ]]; then
            echo -e "  ${XRAY_KEYS}/export/ (raw xray, capability matrix, client templates)"
        fi
    fi
    echo ""
}

status_flow_render_verbose_config_details() {
    [[ -f "$XRAY_CONFIG" ]] || return 0

    echo -e "${BOLD}Детали конфигураций:${NC}"
    local i=0
    local port dest domain sni fp net service decryption flow
    while IFS=$'\t' read -r port dest sni fp net service decryption flow; do
        [[ -z "$port" ]] && continue
        i=$((i + 1))
        domain="${dest%%:*}"

        local port_status="${RED}не слушается${NC}"
        if port_is_listening "$port"; then
            port_status="${GREEN}активен${NC}"
        fi

        local transport_label="endpoint"
        local transport_name="${net:-xhttp}"
        if declare -F transport_endpoint_label > /dev/null 2>&1; then
            transport_label=$(transport_endpoint_label "$net")
        fi
        if declare -F transport_display_name > /dev/null 2>&1; then
            transport_name=$(transport_display_name "${net:-xhttp}")
        fi

        echo -e "  Config ${i}:"
        echo -e "    Порт:        ${port} (${port_status})"
        echo -e "    Домен:       ${domain:-?}"
        echo -e "    SNI:         ${sni:-?}"
        echo -e "    Fingerprint: ${fp:-?}"
        echo -e "    Transport:   ${transport_name}"
        echo -e "    ${transport_label}: ${service:-?}"
        echo -e "    Flow:        ${flow:-${XRAY_DIRECT_FLOW:-xtls-rprx-vision}}"
        echo -e "    Decryption:  ${decryption:-none}"
        echo ""
    done < <(jq -r '
        .inbounds[]
        | select(.listen == "0.0.0.0" or .listen == null)
        | [
            (.port|tostring),
            (.streamSettings.realitySettings.dest // "?"),
            (.streamSettings.realitySettings.serverNames[0] // "?"),
            (.streamSettings.realitySettings.fingerprint // "?"),
            (.streamSettings.network // "xhttp"),
            (.streamSettings.xhttpSettings.path // .streamSettings.grpcSettings.serviceName // .streamSettings.httpSettings.path // "?"),
            (.settings.decryption // "none"),
            (.settings.clients[0].flow // "xtls-rprx-vision")
          ] | @tsv
    ' "$XRAY_CONFIG" 2> /dev/null)
}

status_flow_render_verbose_monitoring() {
    echo -e "${BOLD}Мониторинг:${NC}"
    if systemctl is-active --quiet xray-health.timer 2> /dev/null; then
        echo -e "  Health Timer: ${GREEN}активен${NC}"
        local next_run
        next_run=$(systemctl show xray-health.timer --property=NextElapseUSecRealtime --value 2> /dev/null || echo "unknown")
        echo -e "  Следующая проверка: ${next_run}"
    else
        echo -e "  Health Timer: ${RED}не активен${NC}"
    fi

    if [[ -f "$HEALTH_LOG" ]]; then
        local last_health
        last_health=$(tail -3 "$HEALTH_LOG" 2> /dev/null || echo "нет данных")
        echo -e "  Последние записи:"
        echo "    $last_health"
    fi
    echo ""
}

status_flow_render_verbose_self_check() {
    declare -F self_check_status_summary_tsv > /dev/null 2>&1 || return 0

    local self_check_summary
    self_check_summary=$(self_check_status_summary_tsv 2> /dev/null || true)
    echo -e "${BOLD}Self-check:${NC}"
    if [[ -n "$self_check_summary" ]]; then
        local verdict action checked_at config_name variant_key variant_mode variant_family latency_ms
        IFS=$'\t' read -r verdict action checked_at config_name variant_key variant_mode variant_family latency_ms <<< "$self_check_summary"
        echo -e "  Verdict: ${verdict}"
        echo -e "  Action: ${action}"
        echo -e "  Checked: ${checked_at}"
        echo -e "  Config: ${config_name}"
        echo -e "  Variant: ${variant_key} (${variant_mode}, ${variant_family}, ${latency_ms}ms)"
    else
        echo -e "  Verdict: ${YELLOW}нет данных${NC}"
    fi
    echo ""
}

status_flow_render_verbose_measurements() {
    declare -F operator_decision_payload_json > /dev/null 2>&1 || return 0

    local decision_payload=""
    decision_payload=$(operator_decision_payload_json 2> /dev/null || true)
    echo -e "${BOLD}Field measurements:${NC}"
    if [[ -n "$decision_payload" ]]; then
        local field_verdict operator_recommendation operator_reason coverage_verdict report_count network_tag_count provider_count region_count
        local family_diversity_verdict long_term_verdict rotation_verdict weak_streak latest_generated
        local current_primary current_primary_family current_primary_recommended current_primary_rescue current_primary_trend
        local best_spare best_spare_family best_spare_recommended best_spare_trend recommend_emergency
        local cooldown_families cooldown_domains promotion_block_reason summary_state summary_state_reason rotation_state_status rotation_state_reason
        field_verdict=$(jq -r '.field.field_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        operator_recommendation=$(jq -r '.decision_recommendation // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        operator_reason=$(jq -r '.decision_reason // "n/a"' <<< "$decision_payload" 2> /dev/null || echo "n/a")
        coverage_verdict=$(jq -r '.field.coverage_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        report_count=$(jq -r '.field.report_count // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        network_tag_count=$(jq -r '.field.network_tag_count // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        provider_count=$(jq -r '.field.provider_count // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        region_count=$(jq -r '.field.region_count // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        family_diversity_verdict=$(jq -r '.field.family_diversity_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        long_term_verdict=$(jq -r '.field.long_term_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        summary_state=$(jq -r '.field.summary_state // "missing"' <<< "$decision_payload" 2> /dev/null || echo "missing")
        summary_state_reason=$(jq -r '.field.summary_state_reason // empty' <<< "$decision_payload" 2> /dev/null || true)
        rotation_state_status=$(jq -r '.field.rotation_state_status // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        rotation_state_reason=$(jq -r '.field.rotation_state_reason // empty' <<< "$decision_payload" 2> /dev/null || true)
        rotation_verdict=$(jq -r '.field.rotation_verdict // "keep-current-primary"' <<< "$decision_payload" 2> /dev/null || echo "keep-current-primary")
        weak_streak=$(jq -r '.field.primary_weak_streak // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        current_primary=$(jq -r '.field.current_primary // "n/a"' <<< "$decision_payload" 2> /dev/null || echo "n/a")
        current_primary_family=$(jq -r '.field.current_primary_family // "n/a"' <<< "$decision_payload" 2> /dev/null || echo "n/a")
        current_primary_recommended=$(jq -r '.field.current_primary_stats.recommended_success_rate_last5 // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        current_primary_rescue=$(jq -r '.field.current_primary_stats.rescue_success_rate_last5 // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        current_primary_trend=$(jq -r '.field.current_primary_stats.trend_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        best_spare=$(jq -r '.field.best_spare // "n/a"' <<< "$decision_payload" 2> /dev/null || echo "n/a")
        best_spare_family=$(jq -r '.field.best_spare_family // "n/a"' <<< "$decision_payload" 2> /dev/null || echo "n/a")
        best_spare_recommended=$(jq -r '.field.best_spare_stats.recommended_success_rate_last5 // 0' <<< "$decision_payload" 2> /dev/null || echo 0)
        best_spare_trend=$(jq -r '.field.best_spare_stats.trend_verdict // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        recommend_emergency=$(jq -r '.field.recommend_emergency // false' <<< "$decision_payload" 2> /dev/null || echo false)
        latest_generated=$(jq -r '.field.latest_report_generated // "unknown"' <<< "$decision_payload" 2> /dev/null || echo "unknown")
        cooldown_families=$(jq -r '(.field.cooldown_families // []) | join(", ")' <<< "$decision_payload" 2> /dev/null || true)
        cooldown_domains=$(jq -r '(.field.cooldown_domains // []) | join(", ")' <<< "$decision_payload" 2> /dev/null || true)
        promotion_block_reason=$(jq -r '.field.promotion_block_reason // empty' <<< "$decision_payload" 2> /dev/null || true)
        echo -e "  Verdict: ${field_verdict}"
        echo -e "  Recommendation: ${operator_recommendation}"
        echo -e "  Reason: ${operator_reason}"
        echo -e "  Coverage: ${coverage_verdict} (${report_count} reports, ${network_tag_count} networks, ${provider_count} providers, ${region_count} regions)"
        echo -e "  Family diversity: ${family_diversity_verdict}"
        echo -e "  Long-term trend: ${long_term_verdict}"
        if [[ "$summary_state" != "ok" ]]; then
            echo -e "  Summary state: ${summary_state}${summary_state_reason:+ (${summary_state_reason})}"
        fi
        if [[ "$rotation_state_status" == "invalid" ]]; then
            echo -e "  Rotation state: ${rotation_state_status}${rotation_state_reason:+ (${rotation_state_reason})}"
        fi
        echo -e "  Rotation: ${rotation_verdict} (weak streak ${weak_streak})"
        echo -e "  Current primary: ${current_primary} [${current_primary_family}] (recommended ${current_primary_recommended}%, rescue ${current_primary_rescue}%, trend ${current_primary_trend})"
        echo -e "  Best spare: ${best_spare} [${best_spare_family}] (recommended ${best_spare_recommended}%, trend ${best_spare_trend})"
        echo -e "  Recommend emergency: ${recommend_emergency}"
        if [[ -n "$cooldown_families" || -n "$cooldown_domains" ]]; then
            echo -e "  Cooldowns: families=${cooldown_families:-none}, domains=${cooldown_domains:-none}"
        fi
        if [[ -n "$promotion_block_reason" ]]; then
            echo -e "  Rotation block: ${promotion_block_reason}"
        fi
        echo -e "  Latest report: ${latest_generated}"
    else
        echo -e "  Verdict: ${YELLOW}нет данных${NC}"
    fi
    echo ""
}

status_flow_render_verbose_source() {
    echo -e "${BOLD}Source metadata:${NC}"
    echo -e "  Kind: ${XRAY_SOURCE_KIND:-unknown}"
    echo -e "  Ref: ${XRAY_SOURCE_REF:-unknown}"
    echo -e "  Commit: ${XRAY_SOURCE_COMMIT:-unknown}"
    echo ""
}

status_flow_render_verbose_auto_update() {
    echo -e "${BOLD}Авто-обновления:${NC}"
    if systemctl is-active --quiet xray-auto-update.timer 2> /dev/null; then
        echo -e "  Статус: ${GREEN}включены${NC}"
        local next_update
        next_update=$(systemctl show xray-auto-update.timer --property=NextElapseUSecRealtime --value 2> /dev/null || echo "unknown")
        echo -e "  Следующее обновление: ${next_update}"
    else
        echo -e "  Статус: ${YELLOW}отключены${NC}"
    fi
    echo ""
}

status_flow_render_verbose_system_resources() {
    echo -e "${BOLD}Ресурсы системы:${NC}"
    local mem_info
    mem_info=$(free -m 2> /dev/null | awk 'NR==2{printf "  Память: %sMB / %sMB (%.1f%%)", $3, $2, $3*100/$2}' || true)
    if [[ -z "$mem_info" ]]; then
        mem_info="  Память: n/a"
    fi
    echo -e "$mem_info"

    local disk_info
    disk_info=$(df -h / 2> /dev/null | awk 'NR==2{printf "  Диск:   %s / %s (%s)", $3, $2, $5}' || true)
    if [[ -z "$disk_info" ]]; then
        disk_info="  Диск:   n/a"
    fi
    echo -e "$disk_info"
    echo ""
}

status_flow_render_verbose_details() {
    echo -e "${BOLD}${CYAN}$(ui_section_title_string "Подробная информация")${NC}"
    echo ""
    status_flow_render_verbose_config_details
    status_flow_render_verbose_monitoring
    status_flow_render_verbose_source
    status_flow_render_verbose_self_check
    status_flow_render_verbose_measurements
    status_flow_render_verbose_auto_update
    status_flow_render_verbose_system_resources
    echo ""
}

status_flow() {
    status_flow_render_header
    status_flow_render_runtime
    status_flow_render_config_summary
    status_flow_render_server_info
    status_flow_render_client_artifacts

    if [[ "$VERBOSE" == "true" ]]; then
        status_flow_render_verbose_details
    else
        echo -e "${DIM}Подсказка: используйте --verbose для подробной информации${NC}"
        echo ""
    fi
}

logs_flow() {
    local target="${LOGS_TARGET:-all}"
    local lines=50

    echo ""
    case "$target" in
        xray)
            echo -e "${BOLD}Логи Xray (последние ${lines} строк):${NC}"
            echo ""
            journalctl -u xray -n "$lines" --no-pager 2> /dev/null || {
                echo "journalctl недоступен, пробуем файл..."
                tail -n "$lines" "$XRAY_LOGS/access.log" 2> /dev/null || echo "Логи не найдены"
            }
            ;;
        health)
            echo -e "${BOLD}Логи Health Check (последние ${lines} строк):${NC}"
            echo ""
            if [[ -f "$HEALTH_LOG" ]]; then
                tail -n "$lines" "$HEALTH_LOG"
            else
                journalctl -u xray-health.service -n "$lines" --no-pager 2> /dev/null || echo "Логи health check не найдены"
            fi
            ;;
        all | *)
            echo -e "${BOLD}${CYAN}=== Xray ===${NC}"
            journalctl -u xray -n 20 --no-pager 2> /dev/null || echo "Недоступно"
            echo ""
            echo -e "${BOLD}${CYAN}=== Health Check ===${NC}"
            if [[ -f "$HEALTH_LOG" ]]; then
                tail -n 10 "$HEALTH_LOG"
            else
                journalctl -u xray-health.service -n 10 --no-pager 2> /dev/null || echo "Недоступно"
            fi
            ;;
    esac
    echo ""
}

check_update_flow() {
    echo ""
    echo -e "${BOLD}Проверка обновлений...${NC}"
    echo ""

    local current_version="не установлен"
    if [[ -x "$XRAY_BIN" ]]; then
        current_version=$("$XRAY_BIN" version 2> /dev/null | head -1 | awk '{print $2}' || echo "unknown")
        current_version=$(trim_ws "$current_version")
        [[ -n "$current_version" ]] || current_version="unknown"
    fi
    echo -e "Текущая версия Xray: ${BOLD}${current_version}${NC}"

    local latest_version
    latest_version=$(curl_fetch_text_allowlist "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
        --connect-timeout 10 --max-time 15 2> /dev/null |
        jq -r '.tag_name' 2> /dev/null | sed 's/^v//')

    if [[ -n "$latest_version" && "$latest_version" != "null" ]]; then
        echo -e "Последняя версия Xray: ${BOLD}${latest_version}${NC}"

        if [[ "$current_version" == "не установлен" ]]; then
            echo -e "${YELLOW}Xray не установлен${NC}"
            echo -e "  Выполните: ${CYAN}xray-reality.sh install${NC}"
        elif [[ "$current_version" == "unknown" ]]; then
            echo -e "${YELLOW}Не удалось определить установленную версию${NC}"
            echo -e "  Для обновления выполните: ${CYAN}xray-reality.sh update${NC}"
        elif [[ "$current_version" == "$latest_version" ]]; then
            echo -e "${GREEN}Xray актуален${NC}"
        elif [[ ! "$current_version" =~ ^[0-9]+(\.[0-9]+){1,3}([-.][0-9A-Za-z]+)*$ ]]; then
            echo -e "${YELLOW}Нестандартный формат версии: ${current_version}${NC}"
            echo -e "  Для обновления выполните: ${CYAN}xray-reality.sh update${NC}"
        elif ! declare -F version_lt > /dev/null 2>&1; then
            echo -e "${YELLOW}Не удалось сравнить версии автоматически${NC}"
            echo -e "  Для обновления выполните: ${CYAN}xray-reality.sh update${NC}"
        elif version_lt "$current_version" "$latest_version"; then
            echo -e "${YELLOW}Доступно обновление!${NC}"
            echo -e "  Выполните: ${CYAN}xray-reality.sh update${NC}"
        else
            echo -e "${GREEN}Версия новее чем релиз${NC}"
        fi
    else
        echo -e "${YELLOW}Не удалось проверить последнюю версию${NC}"
    fi

    echo ""
    echo -e "Версия скрипта: ${BOLD}${SCRIPT_VERSION}${NC}"
    echo ""
}
