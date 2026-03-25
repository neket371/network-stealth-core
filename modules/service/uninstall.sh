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

MANAGED_PATHS_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/managed_paths.sh"
if [[ ! -f "$MANAGED_PATHS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    MANAGED_PATHS_MODULE="$XRAY_DATA_DIR/modules/lib/managed_paths.sh"
fi
if [[ ! -f "$MANAGED_PATHS_MODULE" ]]; then
    echo "ERROR: не найден модуль managed paths: $MANAGED_PATHS_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/managed_paths.sh
source "$MANAGED_PATHS_MODULE"

uninstall_path_matches_registry() {
    local path="${1:-}"
    local provider="${2:-}"
    local resolved_path listed_path

    [[ -n "$path" && -n "$provider" ]] || return 1
    declare -F "$provider" > /dev/null 2>&1 || return 1
    resolved_path=$(realpath -m "$path" 2> /dev/null || echo "$path")

    while IFS= read -r listed_path; do
        [[ -n "$listed_path" ]] || continue
        if [[ "$resolved_path" == "$listed_path" ]]; then
            return 0
        fi
    done < <("$provider")
    return 1
}

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
    if [[ -f "${file}.backup" || -L "${file}.backup" ]]; then
        rm -f "${file}.backup"
        echo -e "  ${GREEN}✅ Удалён ${file}.backup${NC}"
    fi
}

uninstall_is_allowed_file_path() {
    local file="$1"
    local resolved_file

    resolved_file=$(realpath -m "$file" 2> /dev/null || echo "$file")
    [[ "$resolved_file" == /* ]] || return 1

    uninstall_path_matches_registry "$resolved_file" managed_systemd_artifact_paths && return 0
    uninstall_path_matches_registry "$resolved_file" managed_runtime_file_paths && return 0
    uninstall_path_matches_registry "$resolved_file" managed_geo_file_paths && return 0

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

uninstall_has_xray_systemd_entries() {
    if ! systemctl_available; then
        return 1
    fi

    if systemctl list-units --all --plain --no-legend 'xray*' 2> /dev/null | grep -q .; then
        return 0
    fi

    if systemctl list-unit-files --plain --no-legend 'xray*' 2> /dev/null | grep -q .; then
        return 0
    fi

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
    local systemd_path
    while IFS= read -r systemd_path; do
        [[ -n "$systemd_path" ]] || continue
        uninstall_remove_file "$systemd_path"
    done < <(managed_systemd_artifact_paths)
}

uninstall_remove_runtime_artifacts() {
    log STEP "Удаляем бинарники и скрипты..."
    local managed_file
    while IFS= read -r managed_file; do
        [[ -n "$managed_file" ]] || continue
        uninstall_remove_file "$managed_file"
    done < <(managed_binary_script_file_paths)

    while IFS= read -r managed_file; do
        [[ -n "$managed_file" ]] || continue
        uninstall_remove_file "$managed_file"
    done < <(managed_geo_file_paths)

    log STEP "Удаляем конфигурации и данные..."
    while IFS= read -r managed_file; do
        [[ -n "$managed_file" ]] || continue
        uninstall_remove_file "$managed_file"
    done < <(managed_config_state_file_paths)

    local managed_dir
    while IFS= read -r managed_dir; do
        [[ -n "$managed_dir" ]] || continue
        uninstall_remove_dir "$managed_dir"
    done < <(managed_config_dir_paths)
}

uninstall_remove_logs_and_auxiliary_artifacts() {
    log STEP "Удаляем логи и бэкапы..."
    local managed_dir
    while IFS= read -r managed_dir; do
        [[ -n "$managed_dir" ]] || continue
        uninstall_remove_dir "$managed_dir"
    done < <(managed_log_backup_dir_paths)

    while IFS= read -r managed_dir; do
        [[ -n "$managed_dir" ]] || continue
        uninstall_remove_dir "$managed_dir"
    done < <(managed_state_dir_paths)

    local managed_log_file
    while IFS= read -r managed_log_file; do
        [[ -n "$managed_log_file" ]] || continue
        uninstall_remove_file "$managed_log_file"
    done < <(managed_log_file_paths)

    log STEP "Удаляем cron и logrotate..."
    local auxiliary_file
    while IFS= read -r auxiliary_file; do
        [[ -n "$auxiliary_file" ]] || continue
        uninstall_remove_file "$auxiliary_file"
    done < <(managed_auxiliary_cleanup_file_paths)

    log STEP "Удаляем системные оптимизации..."
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
        elif ! uninstall_has_xray_systemd_entries; then
            echo -e "  ${DIM}systemctl reset-failed xray*: не требуется${NC}"
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
    if managed_runtime_artifacts_present; then
        return 0
    fi

    if id "$XRAY_USER" > /dev/null 2>&1; then
        return 0
    fi
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}
