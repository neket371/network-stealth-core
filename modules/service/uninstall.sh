#!/usr/bin/env bash
# shellcheck shell=bash

: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_SCRIPT_PATH:=/usr/local/bin/xray-reality.sh}"
: "${XRAY_UPDATE_SCRIPT:=/usr/local/bin/xray-reality-update.sh}"
: "${XRAY_POLICY:=/etc/xray-reality/policy.json}"
: "${XRAY_USER:=xray}"
: "${XRAY_GROUP:=xray}"
: "${XRAY_HOME:=/var/lib/xray}"
: "${XRAY_LOGS:=/var/log/xray}"
: "${XRAY_BACKUP:=/var/backups/xray}"
: "${XRAY_DATA_DIR:=/usr/local/share/xray-reality}"
: "${XRAY_CONFIG:=/etc/xray/config.json}"
: "${XRAY_ENV:=/etc/xray-reality/config.env}"
: "${INSTALL_LOG:=/var/log/xray-install.log}"
: "${UPDATE_LOG:=/var/log/xray-update.log}"
: "${DIAG_LOG:=/var/log/xray-diagnose.log}"
: "${HEALTH_LOG:=/var/log/xray/xray-health.log}"
: "${SELF_CHECK_STATE_FILE:=/var/lib/xray/self-check.json}"
: "${SELF_CHECK_HISTORY_FILE:=/var/lib/xray/self-check-history.ndjson}"
: "${MEASUREMENTS_SUMMARY_FILE:=/var/lib/xray/measurements/latest-summary.json}"
: "${MEASUREMENTS_DIR:=/var/lib/xray/measurements}"
: "${ASSUME_YES:=false}"
: "${NON_INTERACTIVE:=false}"
: "${BOLD:=}"
: "${DIM:=}"
: "${RED:=}"
: "${GREEN:=}"
: "${YELLOW:=}"
: "${NC:=}"

uninstall_remove_file() {
    local file="$1"
    if ! uninstall_is_allowed_file_path "$file"; then
        echo -e "  ${RED}❌ Пропущен небезопасный путь файла: ${file}${NC}"
        return 1
    fi
    if [[ -f "$file" ]]; then
        rm -f "$file"
        echo -e "  ${GREEN}✅ Удалён ${file}${NC}"
    fi
}

uninstall_is_allowed_file_path() {
    local file="$1"
    local resolved_file
    local resolved_candidate
    local candidate
    local basename_file
    local dir

    resolved_file=$(realpath -m "$file" 2> /dev/null || echo "$file")
    [[ "$resolved_file" == /* ]] || return 1

    case "$resolved_file" in
        /etc/systemd/system/xray.service | /etc/systemd/system/xray-health.service | /etc/systemd/system/xray-health.timer | /etc/systemd/system/xray-auto-update.service | /etc/systemd/system/xray-auto-update.timer | /etc/systemd/system/xray-diagnose@.service | /usr/lib/systemd/system/xray.service | /usr/lib/systemd/system/xray-health.service | /usr/lib/systemd/system/xray-health.timer | /usr/lib/systemd/system/xray-auto-update.service | /usr/lib/systemd/system/xray-auto-update.timer | /usr/lib/systemd/system/xray-diagnose@.service | /lib/systemd/system/xray.service | /lib/systemd/system/xray-health.service | /lib/systemd/system/xray-health.timer | /lib/systemd/system/xray-auto-update.service | /lib/systemd/system/xray-auto-update.timer | /lib/systemd/system/xray-diagnose@.service | /usr/local/bin/xray-health.sh | /etc/cron.d/xray-health | /etc/logrotate.d/xray | /etc/sysctl.d/99-xray.conf | /etc/security/limits.d/99-xray.conf | /var/log/xray-install.log | /var/log/xray-update.log | /var/log/xray-diagnose.log | /var/log/xray-repair.log | /var/log/xray-health.log | /var/log/xray.log | /var/lib/xray/self-check.json | /var/lib/xray/self-check-history.ndjson | /var/lib/xray/measurements/latest-summary.json | /etc/xray-reality/policy.json)
            return 0
            ;;
        *) ;;
    esac

    for candidate in "$XRAY_BIN" "$XRAY_SCRIPT_PATH" "$XRAY_UPDATE_SCRIPT" "$INSTALL_LOG" "$UPDATE_LOG" "$DIAG_LOG" "$HEALTH_LOG" "$SELF_CHECK_STATE_FILE" "$SELF_CHECK_HISTORY_FILE" "$MEASUREMENTS_SUMMARY_FILE" "$XRAY_POLICY"; do
        [[ -n "$candidate" ]] || continue
        resolved_candidate=$(realpath -m "$candidate" 2> /dev/null || echo "$candidate")
        if [[ "$resolved_file" == "$resolved_candidate" ]]; then
            case "$(basename "$resolved_file")" in
                xray | xray-reality.sh | xray-reality-update.sh | xray-install.log | xray-update.log | xray-diagnose.log | xray-health.log | self-check.json | self-check-history.ndjson | latest-summary.json | policy.json)
                    return 0
                    ;;
                *) ;;
            esac
            return 1
        fi
    done

    basename_file=$(basename "$resolved_file")
    case "$basename_file" in
        geoip.dat | geosite.dat)
            dir=$(dirname "$resolved_file")
            validate_destructive_path_guard "uninstall geo dirname" "$dir" || return 1
            for candidate in "$(xray_geo_dir)" "$(dirname "$XRAY_BIN")" "/usr/local/share/xray"; do
                [[ -n "$candidate" ]] || continue
                resolved_candidate=$(realpath -m "$candidate" 2> /dev/null || echo "$candidate")
                if [[ "$resolved_file" == "${resolved_candidate}/${basename_file}" ]]; then
                    return 0
                fi
            done
            return 1
            ;;
        *) ;;
    esac

    return 1
}

uninstall_remove_dir() {
    local dir="$1"
    if ! validate_destructive_path_guard "uninstall dir" "$dir"; then
        echo -e "  ${RED}❌ Пропущен небезопасный путь директории: ${dir}${NC}"
        return 1
    fi
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        echo -e "  ${GREEN}✅ Удалена директория ${dir}${NC}"
    fi
}

uninstall_close_ports() {
    local -a ports_to_close=()
    if [[ -f "$XRAY_CONFIG" ]] && command -v jq > /dev/null 2>&1; then
        mapfile -t ports_to_close < <(jq -r '.inbounds[].port // empty' "$XRAY_CONFIG" 2> /dev/null | sort -u)
    fi

    if [[ ${#ports_to_close[@]} -eq 0 ]]; then
        echo -e "  ${DIM}Нет портов для закрытия${NC}"
        return 0
    fi

    if command -v ufw > /dev/null 2>&1; then
        for port in "${ports_to_close[@]}"; do
            if ufw --force delete allow "${port}/tcp" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅ Закрыт порт ${port}/tcp (ufw)${NC}"
            fi
        done
    elif command -v firewall-cmd > /dev/null 2>&1; then
        for port in "${ports_to_close[@]}"; do
            if firewall-cmd --permanent --remove-port="${port}/tcp" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅ Закрыт порт ${port}/tcp (firewalld)${NC}"
            fi
        done
        firewall-cmd --reload > /dev/null 2>&1 || true
    elif command -v iptables > /dev/null 2>&1; then
        for port in "${ports_to_close[@]}"; do
            if iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2> /dev/null; then
                echo -e "  ${GREEN}✅ Закрыт порт ${port}/tcp (iptables)${NC}"
            fi
            if command -v ip6tables > /dev/null 2>&1; then
                ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT 2> /dev/null || true
            fi
        done
    fi
}

uninstall_terminate_user_processes() {
    local user_name="${1:-}"
    [[ -n "$user_name" ]] || return 0
    if ! id "$user_name" > /dev/null 2>&1; then
        return 0
    fi

    if command -v loginctl > /dev/null 2>&1; then
        loginctl terminate-user "$user_name" > /dev/null 2>&1 || true
    fi

    if command -v pkill > /dev/null 2>&1; then
        pkill -TERM -u "$user_name" > /dev/null 2>&1 || true
        sleep 1
        if command -v pgrep > /dev/null 2>&1 && pgrep -u "$user_name" > /dev/null 2>&1; then
            pkill -KILL -u "$user_name" > /dev/null 2>&1 || true
            sleep 1
        fi
    fi
}

uninstall_remove_user_account() {
    local user_name="${1:-}"
    [[ -n "$user_name" ]] || return 0

    local retries_left=3
    while ((retries_left > 0)); do
        if ! id "$user_name" > /dev/null 2>&1; then
            return 0
        fi
        uninstall_terminate_user_processes "$user_name"
        userdel -r "$user_name" > /dev/null 2>&1 || userdel "$user_name" > /dev/null 2>&1 || true
        if ! id "$user_name" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        retries_left=$((retries_left - 1))
    done

    return 1
}

uninstall_remove_group_account() {
    local group_name="${1:-}"
    [[ -n "$group_name" ]] || return 0

    local retries_left=3
    while ((retries_left > 0)); do
        if ! getent group "$group_name" > /dev/null 2>&1; then
            return 0
        fi
        groupdel "$group_name" > /dev/null 2>&1 || true
        if ! getent group "$group_name" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        retries_left=$((retries_left - 1))
    done

    return 1
}

uninstall_render_intro() {
    if [[ "$require_confirmation" == "true" ]]; then
        tty_print_line "$tty_write_fd" ""
        tty_print_box "$tty_write_fd" "$RED" "$uninstall_title" 60 90
        tty_print_line "$tty_write_fd" ""
        tty_printf "$tty_write_fd" '%b⚠️  Будет удалено ВСЁ, связанное с Network Stealth Core:%b\n' "$YELLOW" "$NC"
        tty_print_line "$tty_write_fd" "  • Сервисы и таймеры systemd"
        tty_print_line "$tty_write_fd" "  • Бинарники и скрипты"
        tty_print_line "$tty_write_fd" "  • Конфигурации и ключи"
        tty_print_line "$tty_write_fd" "  • Логи и бэкапы"
        tty_print_line "$tty_write_fd" "  • Правила файрвола"
        tty_print_line "$tty_write_fd" "  • Системные оптимизации"
        tty_print_line "$tty_write_fd" "  • Пользователь и группа xray"
        tty_print_line "$tty_write_fd" ""
        return 0
    fi

    echo ""
    echo -e "${BOLD}${RED}$(ui_box_border_string top "$uninstall_box_width")${NC}"
    echo -e "${BOLD}${RED}$(ui_box_line_string "$uninstall_title" "$uninstall_box_width")${NC}"
    echo -e "${BOLD}${RED}$(ui_box_border_string bottom "$uninstall_box_width")${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Будет удалено ВСЁ, связанное с Network Stealth Core:${NC}"
    echo "  • Сервисы и таймеры systemd"
    echo "  • Бинарники и скрипты"
    echo "  • Конфигурации и ключи"
    echo "  • Логи и бэкапы"
    echo "  • Правила файрвола"
    echo "  • Системные оптимизации"
    echo "  • Пользователь и группа xray"
    echo ""
}

uninstall_confirm_if_needed() {
    if [[ "$require_confirmation" == "true" ]]; then
        local prompt_rc=0
        prompt_yes_no_from_tty \
            "$tty_read_fd" \
            "Вы уверены? Введите yes для подтверждения или no для отмены: " \
            "Введите yes или no (без кавычек)" \
            "$tty_write_fd"
        prompt_rc=$?
        exec {tty_read_fd}<&-
        exec {tty_write_fd}>&-
        if ((prompt_rc == 1)); then
            log INFO "Удаление отменено"
            exit 0
        fi
        if ((prompt_rc != 0)); then
            log ERROR "Не удалось прочитать подтверждение из /dev/tty"
            exit 1
        fi
        return 0
    fi

    log INFO "Неблокирующее удаление: подтверждение пропущено (--yes/non-interactive)"
}

uninstall_detect_systemd_mode() {
    manage_systemd_uninstall=true
    if ! systemctl_available; then
        manage_systemd_uninstall=false
        log INFO "systemctl не найден; systemd-операции удаления пропущены"
    elif ! systemd_running; then
        manage_systemd_uninstall=false
        log INFO "systemd не запущен; systemd-операции удаления пропущены"
    fi
}

uninstall_remove_systemd_artifacts() {
    log STEP "Останавливаем сервисы..."
    local -a services=(xray xray-health.service xray-health.timer xray-auto-update.service xray-auto-update.timer)
    if [[ "$manage_systemd_uninstall" == true ]]; then
        local svc
        for svc in "${services[@]}"; do
            if systemctl is-active --quiet "$svc" 2> /dev/null; then
                if systemctl_uninstall_bounded stop "$svc"; then
                    echo -e "  ${GREEN}✅ Остановлен ${svc}${NC}"
                else
                    echo -e "  ${YELLOW}⚠️  Не удалось остановить ${svc}${NC}"
                fi
            fi
            if ! systemctl_uninstall_bounded disable "$svc"; then
                echo -e "  ${YELLOW}⚠️  Не удалось отключить ${svc}${NC}"
            fi
        done
    else
        echo -e "  ${DIM}Пропущено: systemd недоступен${NC}"
    fi

    log STEP "Закрываем порты в файрволе..."
    uninstall_close_ports

    log STEP "Удаляем systemd-сервисы..."
    uninstall_remove_file /etc/systemd/system/xray.service
    uninstall_remove_file /etc/systemd/system/xray-health.service
    uninstall_remove_file /etc/systemd/system/xray-health.timer
    uninstall_remove_file /etc/systemd/system/xray-auto-update.service
    uninstall_remove_file /etc/systemd/system/xray-auto-update.timer
    uninstall_remove_file /etc/systemd/system/xray-diagnose@.service
}

uninstall_remove_runtime_artifacts() {
    log STEP "Удаляем бинарники и скрипты..."
    uninstall_remove_file "$XRAY_BIN"
    uninstall_remove_file "$XRAY_SCRIPT_PATH"
    uninstall_remove_file "$XRAY_UPDATE_SCRIPT"
    uninstall_remove_file /usr/local/bin/xray-health.sh

    local -a geo_dirs=()
    geo_dirs+=("$(xray_geo_dir)")
    geo_dirs+=("$(dirname "$XRAY_BIN")")
    geo_dirs+=("/usr/local/share/xray")
    local seen_geo_dirs="|"
    local geo_dir
    for geo_dir in "${geo_dirs[@]}"; do
        [[ -n "$geo_dir" ]] || continue
        geo_dir="${geo_dir%/}"
        if [[ "$seen_geo_dirs" == *"|${geo_dir}|"* ]]; then
            continue
        fi
        seen_geo_dirs+="${geo_dir}|"
        uninstall_remove_file "${geo_dir}/geoip.dat"
        uninstall_remove_file "${geo_dir}/geosite.dat"
    done

    log STEP "Удаляем конфигурации и данные..."
    uninstall_remove_dir /etc/xray
    uninstall_remove_dir /etc/xray-reality
    uninstall_remove_dir "$XRAY_DATA_DIR"
    uninstall_remove_file "$XRAY_POLICY"
}

uninstall_remove_logs_and_auxiliary_artifacts() {
    log STEP "Удаляем логи и бэкапы..."
    uninstall_remove_dir "$XRAY_LOGS"
    uninstall_remove_dir "$XRAY_BACKUP"
    uninstall_remove_file "$INSTALL_LOG"
    uninstall_remove_file "$UPDATE_LOG"
    uninstall_remove_file "$DIAG_LOG"
    uninstall_remove_file "$HEALTH_LOG"
    uninstall_remove_file "$SELF_CHECK_STATE_FILE"
    uninstall_remove_file "$SELF_CHECK_HISTORY_FILE"
    uninstall_remove_file "$MEASUREMENTS_SUMMARY_FILE"
    uninstall_remove_dir "$MEASUREMENTS_DIR"

    log STEP "Удаляем cron и logrotate..."
    uninstall_remove_file /etc/cron.d/xray-health
    uninstall_remove_file /etc/logrotate.d/xray

    log STEP "Удаляем системные оптимизации..."
    uninstall_remove_file /etc/sysctl.d/99-xray.conf
    uninstall_remove_file /etc/security/limits.d/99-xray.conf
    sysctl --system > /dev/null 2>&1 || true
}

uninstall_remove_accounts_and_reload() {
    log STEP "Удаляем пользователя и группу..."
    if id "$XRAY_USER" > /dev/null 2>&1; then
        if uninstall_remove_user_account "$XRAY_USER"; then
            echo -e "  ${GREEN}✅ Удалён пользователь ${XRAY_USER}${NC}"
        else
            uninstall_cleanup_failed=true
            echo -e "  ${YELLOW}⚠️  Не удалось удалить пользователя ${XRAY_USER}${NC}"
        fi
    fi
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        if uninstall_remove_group_account "$XRAY_GROUP"; then
            echo -e "  ${GREEN}✅ Удалена группа ${XRAY_GROUP}${NC}"
        else
            uninstall_cleanup_failed=true
            echo -e "  ${YELLOW}⚠️  Не удалось удалить группу ${XRAY_GROUP}${NC}"
        fi
    fi
    uninstall_remove_dir "$XRAY_HOME"

    if [[ "$manage_systemd_uninstall" == true ]]; then
        if systemctl_uninstall_bounded daemon-reload; then
            echo -e "  ${GREEN}✅ systemctl daemon-reload${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Не удалось выполнить systemctl daemon-reload${NC}"
        fi
        if systemctl_uninstall_bounded reset-failed xray.service xray-health.service xray-health.timer xray-auto-update.service xray-auto-update.timer; then
            echo -e "  ${GREEN}✅ systemctl reset-failed xray*${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Не удалось выполнить systemctl reset-failed для xray unit'ов${NC}"
        fi
    fi
}

uninstall_render_done() {
    local uninstall_done_title uninstall_done_width
    uninstall_done_title="УДАЛЕНИЕ ЗАВЕРШЕНО"
    uninstall_done_width=$(ui_box_width_for_lines 60 90 "$uninstall_done_title")
    echo ""
    echo -e "${BOLD}${GREEN}$(ui_box_border_string top "$uninstall_done_width")${NC}"
    echo -e "${BOLD}${GREEN}$(ui_box_line_string "$uninstall_done_title" "$uninstall_done_width")${NC}"
    echo -e "${BOLD}${GREEN}$(ui_box_border_string bottom "$uninstall_done_width")${NC}"
    echo ""
}

uninstall_all() {
    local uninstall_box_width uninstall_title
    uninstall_title="УДАЛЕНИЕ NETWORK STEALTH CORE"
    uninstall_box_width=$(ui_box_width_for_lines 60 90 "$uninstall_title")
    local tty_read_fd=""
    local tty_write_fd=""
    local require_confirmation=false
    if [[ "$ASSUME_YES" != "true" && "$NON_INTERACTIVE" != "true" ]]; then
        require_confirmation=true
        if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
            log ERROR "Требуется интерактивное подтверждение удаления, но /dev/tty недоступен"
            hint "Повторите команду с --yes --non-interactive для явного подтверждения"
            exit 1
        fi
        if ! open_interactive_tty_fds tty_read_fd tty_write_fd; then
            log ERROR "Требуется интерактивное подтверждение удаления, но /dev/tty недоступен"
            hint "Повторите команду с --yes --non-interactive для явного подтверждения"
            exit 1
        fi
    fi

    uninstall_render_intro
    uninstall_confirm_if_needed

    if ! validate_destructive_runtime_paths; then
        log ERROR "Операция uninstall заблокирована: обнаружены небезопасные runtime-пути"
        exit 1
    fi

    echo ""
    set +e

    local manage_systemd_uninstall=true
    local uninstall_cleanup_failed=false
    uninstall_detect_systemd_mode
    uninstall_remove_systemd_artifacts
    uninstall_remove_runtime_artifacts
    uninstall_remove_logs_and_auxiliary_artifacts
    uninstall_remove_accounts_and_reload

    set -e

    uninstall_render_done

    if [[ "$uninstall_cleanup_failed" == true ]]; then
        log ERROR "Удаление завершилось с остаточными артефактами пользователей/групп"
        return 1
    fi
}

uninstall_has_managed_artifacts() {
    local candidate
    local -a core_paths=(
        "/etc/systemd/system/xray.service"
        "/etc/systemd/system/xray-health.service"
        "/etc/systemd/system/xray-health.timer"
        "/etc/systemd/system/xray-auto-update.service"
        "/etc/systemd/system/xray-auto-update.timer"
        "/etc/systemd/system/xray-diagnose@.service"
        "$XRAY_BIN"
        "$XRAY_SCRIPT_PATH"
        "$XRAY_UPDATE_SCRIPT"
        "$XRAY_CONFIG"
        "$XRAY_ENV"
        "$XRAY_POLICY"
        "$SELF_CHECK_STATE_FILE"
        "$SELF_CHECK_HISTORY_FILE"
        "$MEASUREMENTS_SUMMARY_FILE"
        "$MEASUREMENTS_DIR"
        "/etc/xray"
        "/etc/xray-reality"
        "$XRAY_DATA_DIR"
        "$XRAY_HOME"
        "$XRAY_BACKUP"
    )
    for candidate in "${core_paths[@]}"; do
        [[ -n "$candidate" ]] || continue
        if [[ -e "$candidate" ]]; then
            return 0
        fi
    done

    if id "$XRAY_USER" > /dev/null 2>&1; then
        return 0
    fi
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}
