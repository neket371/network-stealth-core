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

CONFIG_SHARED_HELPERS_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_SHARED_HELPERS_MODULE"
fi

sanitize_systemd_value() {
    local out_name="$1"
    local value="${2:-}"
    local sanitized
    sanitized=$(printf '%s' "$value" | tr -d '\000-\037\177')
    printf -v "$out_name" '%s' "$sanitized"
}

sanitize_systemd_value_into() {
    local out_name="$1"
    local value="${2:-}"
    sanitize_systemd_value "$out_name" "$value"
}

validate_systemd_user_group_value() {
    local value="$1"
    local field="$2"
    if [[ -z "$value" || ! "$value" =~ ^[a-z_][a-z0-9_-]*\$?$ ]]; then
        log ERROR "Небезопасное значение ${field} для systemd unit: ${value}"
        return 1
    fi
    return 0
}

validate_systemd_path_value() {
    local value="$1"
    local field="$2"
    if [[ -z "$value" || ! "$value" =~ ^/[A-Za-z0-9._/@:+-]+$ ]]; then
        log ERROR "Небезопасный путь ${field} для systemd unit: ${value}"
        return 1
    fi
    return 0
}

is_nonfatal_systemctl_error() {
    local err="${1:-}"
    [[ -n "$err" ]] || return 1
    case "$err" in
        *"System has not been booted with systemd"* | *"Failed to connect to bus"* | *"Host is down"* | *"Transport endpoint is not connected"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

systemctl_uninstall_bounded() {
    local action="$1"
    local unit="${2:-}"
    local timeout_s="${XRAY_SYSTEMCTL_UNINSTALL_TIMEOUT:-30}"
    if [[ ! "$timeout_s" =~ ^[0-9]+$ ]] || ((timeout_s < 5 || timeout_s > 300)); then
        timeout_s=30
    fi

    local cmd_desc="systemctl ${action}"
    if [[ -n "$unit" ]]; then
        cmd_desc+=" ${unit}"
    fi

    local rc=0
    local err=""
    if command -v timeout > /dev/null 2>&1; then
        if [[ -n "$unit" ]]; then
            err=$(timeout --signal=TERM --kill-after=10s "${timeout_s}s" systemctl "$action" "$unit" 2>&1) || rc=$?
        else
            err=$(timeout --signal=TERM --kill-after=10s "${timeout_s}s" systemctl "$action" 2>&1) || rc=$?
        fi
        if ((rc == 124 || rc == 137)); then
            log WARN "${cmd_desc} превысил таймаут ${timeout_s}s; продолжаем удаление"
            debug_file "${cmd_desc} timeout (${timeout_s}s): ${err}"
            return "$rc"
        fi
    else
        if [[ -n "$unit" ]]; then
            err=$(systemctl "$action" "$unit" 2>&1) || rc=$?
        else
            err=$(systemctl "$action" 2>&1) || rc=$?
        fi
    fi

    if ((rc != 0)); then
        if is_nonfatal_systemctl_error "$err"; then
            debug_file "${cmd_desc} non-fatal: ${err}"
            return 0
        fi
        debug_file "${cmd_desc} failed: ${err}"
        return "$rc"
    fi

    return 0
}

cleanup_conflicting_xray_service_dropins() {
    local dropin_dir="/etc/systemd/system/xray.service.d"
    [[ -d "$dropin_dir" ]] || return 0

    local -a dropin_files=()
    while IFS= read -r -d '' dropin_file; do
        dropin_files+=("$dropin_file")
    done < <(find "$dropin_dir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -name '*.conf' -print0 2> /dev/null | sort -z)

    if ((${#dropin_files[@]} == 0)); then
        return 0
    fi

    local cleaned_any=false
    local runtime_override_regex='^[[:space:]]*(ExecStart|ExecStartPre|ExecStartPost|ExecReload|User|Group|WorkingDirectory|Environment(File)?|DynamicUser|SupplementaryGroups|RootDirectory|RootImage|PermissionsStartOnly|UMask)[[:space:]]*='
    local dropin_file
    for dropin_file in "${dropin_files[@]}"; do
        local conflicting=false
        if [[ ! -r "$dropin_file" ]]; then
            conflicting=true
            log WARN "systemd drop-in недоступен для чтения; отключаем в safe-mode: ${dropin_file}"
        elif grep -Eiq "$runtime_override_regex" "$dropin_file"; then
            conflicting=true
        fi

        if [[ "$conflicting" != true ]]; then
            continue
        fi
        backup_file "$dropin_file"
        if ! rm -f "$dropin_file"; then
            log ERROR "Не удалось удалить конфликтный systemd drop-in: ${dropin_file}"
            return 1
        fi
        cleaned_any=true
        log WARN "Отключён конфликтный systemd drop-in: ${dropin_file}"
    done

    if [[ "$cleaned_any" == true ]]; then
        if find "$dropin_dir" -mindepth 1 -maxdepth 1 | read -r _; then
            :
        else
            rmdir "$dropin_dir" 2> /dev/null || true
        fi
    fi

    return 0
}

create_systemd_service() {
    log STEP "Создаём systemd сервис..."

    local manage_systemd=true
    if ! systemctl_available; then
        log WARN "systemctl не найден; сервис будет создан без активации"
        manage_systemd=false
    elif ! systemd_running; then
        log WARN "systemd не запущен; сервис будет создан без активации"
        manage_systemd=false
    fi

    local systemd_dir="/etc/systemd/system"
    if [[ ! -d "$systemd_dir" ]]; then
        if ! install -d -m 755 "$systemd_dir" 2> /dev/null; then
            if [[ "$manage_systemd" == true ]]; then
                log ERROR "Не удалось создать каталог ${systemd_dir} для unit-файлов"
                return 1
            fi
            log WARN "Каталог ${systemd_dir} недоступен; создание unit-файла пропущено"
            return 0
        fi
    fi

    local _sd_user _sd_group _sd_logs _sd_bin _sd_config
    sanitize_systemd_value_into _sd_user "$XRAY_USER"
    sanitize_systemd_value_into _sd_group "$XRAY_GROUP"
    sanitize_systemd_value_into _sd_logs "$XRAY_LOGS"
    sanitize_systemd_value_into _sd_bin "$XRAY_BIN"
    sanitize_systemd_value_into _sd_config "$XRAY_CONFIG"
    validate_systemd_user_group_value "$_sd_user" "XRAY_USER" || return 1
    validate_systemd_user_group_value "$_sd_group" "XRAY_GROUP" || return 1
    validate_systemd_path_value "$_sd_logs" "XRAY_LOGS" || return 1
    validate_systemd_path_value "$_sd_bin" "XRAY_BIN" || return 1
    validate_systemd_path_value "$_sd_config" "XRAY_CONFIG" || return 1

    cleanup_conflicting_xray_service_dropins || return 1

    backup_file /etc/systemd/system/xray.service
    atomic_write /etc/systemd/system/xray.service 0644 << EOF
[Unit]
Description=Xray Service (Network Stealth Core ${SCRIPT_VERSION})
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
OnFailure=xray-diagnose@%n.service

[Service]
Type=simple
User=${_sd_user}
Group=${_sd_group}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectProc=invisible
ProtectClock=yes
PrivateDevices=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=true
SystemCallFilter=@system-service @network-io
SystemCallFilter=~@privileged @mount @swap @reboot @raw-io @cpu-emulation @debug @obsolete
PrivateTmp=true
ReadWritePaths=${_sd_logs}
ExecStart=${_sd_bin} run -config ${_sd_config}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    if [[ "$manage_systemd" == true ]]; then
        local daemon_reload_err=""
        local daemon_reload_rc=0
        systemctl_run_bounded --err-var daemon_reload_err daemon-reload || daemon_reload_rc=$?
        if ((daemon_reload_rc != 0)); then
            if is_nonfatal_systemctl_error "$daemon_reload_err"; then
                log WARN "systemd недоступен для активации unit; продолжаем без enable"
                debug_file "systemctl daemon-reload skipped: ${daemon_reload_err}"
                manage_systemd=false
                SYSTEMD_MANAGEMENT_DISABLED=true
            else
                log ERROR "Не удалось перезагрузить конфигурацию systemd"
                debug_file "systemctl daemon-reload failed: ${daemon_reload_err}"
                return 1
            fi
        fi

        if [[ "$manage_systemd" == true ]]; then
            local enable_err=""
            local enable_rc=0
            systemctl_run_bounded --err-var enable_err enable xray || enable_rc=$?
            if ((enable_rc != 0)); then
                if is_nonfatal_systemctl_error "$enable_err"; then
                    log WARN "systemd недоступен для enable xray; продолжаем без активации"
                    debug_file "systemctl enable xray skipped: ${enable_err}"
                    manage_systemd=false
                    SYSTEMD_MANAGEMENT_DISABLED=true
                else
                    log ERROR "Не удалось включить сервис Xray"
                    debug_file "systemctl enable xray failed: ${enable_err}"
                    return 1
                fi
            fi
        fi

        if [[ "$manage_systemd" == true ]]; then
            log OK "Systemd сервис создан"
        else
            log WARN "Unit-файл создан; активация systemd пропущена"
        fi
    else
        SYSTEMD_MANAGEMENT_DISABLED=true
        log WARN "Unit-файл создан; активируйте сервис вручную при наличии systemd"
    fi
}

setup_diagnose_service() {
    log STEP "Настраиваем диагностику при сбоях..."

    if ! systemctl_available; then
        log WARN "systemctl не найден; диагностика через systemd отключена"
        return 0
    fi
    if ! systemd_running; then
        log WARN "systemd не запущен; диагностика через systemd отключена"
        return 0
    fi

    local safe_script_path
    sanitize_systemd_value_into safe_script_path "$XRAY_SCRIPT_PATH"
    validate_systemd_path_value "$safe_script_path" "XRAY_SCRIPT_PATH" || return 1

    backup_file /etc/systemd/system/xray-diagnose@.service
    atomic_write /etc/systemd/system/xray-diagnose@.service 0644 << EOF
[Unit]
Description=Xray Diagnose (%i)
After=network.target

[Service]
Type=oneshot
Environment=FAILED_UNIT=%i
ExecStart=${safe_script_path} diagnose --non-interactive
EOF

    if systemctl_run_bounded daemon-reload; then
        log OK "Диагностика включена"
    else
        log WARN "Не удалось включить диагностику через systemd"
    fi
}

configure_firewall() {
    log STEP "Настраиваем файрвол..."

    # shellcheck disable=SC2153 # PORTS/PORTS_V6 are globals from config.sh
    local ports_v4=("${PORTS[@]}")
    local ports_v6=()
    # shellcheck disable=SC2153
    if [[ "$HAS_IPV6" == true ]]; then
        ports_v6=("${PORTS_V6[@]}")
    fi
    local all_ports=("${ports_v4[@]}" "${ports_v6[@]}")
    local fw_status
    fw_status=$(open_firewall_ports "${ports_v4[*]}" "${ports_v6[*]}")
    case "$fw_status" in
        ok)
            log OK "Файрвол настроен"
            ;;
        partial)
            log WARN "Файрвол настроен частично - проверьте правила"
            ;;
        skipped)
            log INFO "Автоматическая настройка файрвола пропущена"
            log INFO "Откройте порты вручную: ${all_ports[*]}"
            ;;
        *)
            log WARN "Неизвестный статус настройки файрвола: ${fw_status}"
            log INFO "Откройте порты вручную: ${all_ports[*]}"
            ;;
    esac
}

start_services() {
    log STEP "Запускаем Xray..."

    if ! systemctl_available; then
        log WARN "systemctl не найден; запуск сервисов пропущен"
        return 0
    fi
    if ! systemd_running; then
        log WARN "systemd не запущен; запуск сервисов пропущен"
        return 0
    fi

    local restart_err=""
    if ! systemctl_restart_xray_bounded restart_err; then
        if is_nonfatal_systemctl_error "$restart_err"; then
            log WARN "systemd недоступен для restart xray; запуск сервисов пропущен"
            debug_file "systemctl restart xray skipped: ${restart_err}"
            SYSTEMD_MANAGEMENT_DISABLED=true
            return 0
        fi
        log ERROR "Не удалось перезапустить Xray через systemd"
        return 1
    fi

    local wait_count=0
    while ((wait_count < 10)); do
        if systemctl is-active --quiet xray; then
            break
        fi
        sleep 1
        ((wait_count += 1))
    done

    if ! systemctl is-active --quiet xray; then
        log ERROR "Xray не запустился!"
        hint "Проверьте порты: lsof -i :443 | другой сервис может занимать порт"
        hint "Проверьте конфиг: xray-reality.sh diagnose"
        journalctl -u xray -n 30 --no-pager
        if [[ "$AUTO_ROLLBACK" == true ]]; then
            local latest_backup=""
            assign_latest_backup_dir latest_backup || true
            if [[ -n "$latest_backup" ]]; then
                log WARN "Пробуем авто-откат из $latest_backup"
                rollback_from_session "$latest_backup"
                if systemctl is-active --quiet xray; then
                    log OK "Авто-откат успешен"
                else
                    log ERROR "Авто-откат не помог"
                    exit 1
                fi
            else
                log WARN "Авто-откат невозможен: бэкапы не найдены"
                exit 1
            fi
        else
            exit 1
        fi
    fi

    log OK "Xray запущен"
}

update_xray() {
    log STEP "Обновляем Xray-core..."
    local artifact
    for artifact in \
        "$XRAY_CONFIG" \
        "$XRAY_KEYS/keys.txt" \
        "$XRAY_KEYS/clients.txt" \
        "$XRAY_KEYS/clients.json" \
        "$XRAY_KEYS/export/raw-xray-index.json" \
        "$XRAY_KEYS/export/capabilities.json" \
        "$SELF_CHECK_STATE_FILE"; do
        [[ -f "$artifact" ]] || continue
        backup_file "$artifact"
    done
    backup_file "$XRAY_BIN"
    install_minisign
    install_xray

    if [[ -f "$XRAY_CONFIG" ]]; then
        if ! xray_config_test_ok "$XRAY_CONFIG"; then
            log ERROR "Xray отклонил конфигурацию после обновления"
            exit 1
        fi
    fi

    if systemd_running && systemctl list-unit-files --type=service 2> /dev/null | grep -q "^xray.service"; then
        local restart_err=""
        if ! systemctl_restart_xray_bounded restart_err; then
            log ERROR "Не удалось перезапустить Xray после обновления"
            exit 1
        fi
    fi
    log OK "Xray обновлён"
}

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

    if systemd_running && systemctl list-unit-files --type=service 2> /dev/null | grep -q "^xray.service"; then
        if systemctl is-active --quiet xray 2> /dev/null; then
            if ! systemctl_uninstall_bounded stop xray; then
                log ERROR "Не удалось остановить xray перед откатом"
                exit 1
            fi
        fi
    fi

    (
        cd "$session_dir" || exit 1
        find . -type f -print0 | while IFS= read -r -d '' file; do
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

            mkdir -p "$(dirname "$dest")"
            cp -a "$session_dir/$rel" "$dest"
            log INFO "Восстановлен: $dest"
        done
    )

    if systemd_running; then
        if ! systemctl_uninstall_bounded daemon-reload; then
            log WARN "Не удалось выполнить systemctl daemon-reload после отката"
        fi
        local restart_err=""
        if ! systemctl_restart_xray_bounded restart_err; then
            log WARN "Не удалось перезапустить xray после отката"
        fi
    else
        log WARN "systemd не запущен; перезапуск сервисов пропущен"
    fi

    log OK "Откат завершён"
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
        /etc/systemd/system/xray.service | /etc/systemd/system/xray-health.service | /etc/systemd/system/xray-health.timer | /etc/systemd/system/xray-auto-update.service | /etc/systemd/system/xray-auto-update.timer | /etc/systemd/system/xray-diagnose@.service | /usr/lib/systemd/system/xray.service | /usr/lib/systemd/system/xray-health.service | /usr/lib/systemd/system/xray-health.timer | /usr/lib/systemd/system/xray-auto-update.service | /usr/lib/systemd/system/xray-auto-update.timer | /usr/lib/systemd/system/xray-diagnose@.service | /lib/systemd/system/xray.service | /lib/systemd/system/xray-health.service | /lib/systemd/system/xray-health.timer | /lib/systemd/system/xray-auto-update.service | /lib/systemd/system/xray-auto-update.timer | /lib/systemd/system/xray-diagnose@.service | /usr/local/bin/xray-health.sh | /etc/cron.d/xray-health | /etc/logrotate.d/xray | /etc/sysctl.d/99-xray.conf | /etc/security/limits.d/99-xray.conf | /var/log/xray-install.log | /var/log/xray-update.log | /var/log/xray-diagnose.log | /var/log/xray-repair.log | /var/log/xray-health.log | /var/log/xray.log | /var/lib/xray/self-check.json)
            return 0
            ;;
        *) ;;
    esac

    for candidate in "$XRAY_BIN" "$XRAY_SCRIPT_PATH" "$XRAY_UPDATE_SCRIPT" "$INSTALL_LOG" "$UPDATE_LOG" "$DIAG_LOG" "$HEALTH_LOG" "$SELF_CHECK_STATE_FILE"; do
        [[ -n "$candidate" ]] || continue
        resolved_candidate=$(realpath -m "$candidate" 2> /dev/null || echo "$candidate")
        if [[ "$resolved_file" == "$resolved_candidate" ]]; then
            case "$(basename "$resolved_file")" in
                xray | xray-reality.sh | xray-reality-update.sh | xray-install.log | xray-update.log | xray-diagnose.log | xray-health.log | self-check.json)
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

uninstall_all() {
    local uninstall_box_width uninstall_title
    uninstall_title="УДАЛЕНИЕ NETWORK STEALTH CORE"
    uninstall_box_width=$(ui_box_width_for_lines 60 90 "$uninstall_title")
    local tty_fd=""
    local require_confirmation=false
    if [[ "$ASSUME_YES" != "true" && "$NON_INTERACTIVE" != "true" ]]; then
        require_confirmation=true
        if [[ ! -t 0 && ! -t 1 && ! -t 2 ]]; then
            log ERROR "Требуется интерактивное подтверждение удаления, но /dev/tty недоступен"
            hint "Повторите команду с --yes --non-interactive для явного подтверждения"
            exit 1
        fi
        if ! open_interactive_tty_fd tty_fd; then
            log ERROR "Требуется интерактивное подтверждение удаления, но /dev/tty недоступен"
            hint "Повторите команду с --yes --non-interactive для явного подтверждения"
            exit 1
        fi
    fi

    if [[ "$require_confirmation" == "true" ]]; then
        tty_print_line "$tty_fd" ""
        tty_print_box "$tty_fd" "$RED" "$uninstall_title" 60 90
        tty_print_line "$tty_fd" ""
        tty_printf "$tty_fd" '%b⚠️  Будет удалено ВСЁ, связанное с Network Stealth Core:%b\n' "$YELLOW" "$NC"
        tty_print_line "$tty_fd" "  • Сервисы и таймеры systemd"
        tty_print_line "$tty_fd" "  • Бинарники и скрипты"
        tty_print_line "$tty_fd" "  • Конфигурации и ключи"
        tty_print_line "$tty_fd" "  • Логи и бэкапы"
        tty_print_line "$tty_fd" "  • Правила файрвола"
        tty_print_line "$tty_fd" "  • Системные оптимизации"
        tty_print_line "$tty_fd" "  • Пользователь и группа xray"
        tty_print_line "$tty_fd" ""
    else
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
    fi

    if [[ "$require_confirmation" == "true" ]]; then
        local prompt_rc=0
        prompt_yes_no_from_tty \
            "$tty_fd" \
            "Вы уверены? Введите yes для подтверждения или no для отмены: " \
            "Введите yes или no (без кавычек)"
        prompt_rc=$?
        exec {tty_fd}>&-
        if ((prompt_rc == 1)); then
            log INFO "Удаление отменено"
            exit 0
        fi
        if ((prompt_rc != 0)); then
            log ERROR "Не удалось прочитать подтверждение из /dev/tty"
            exit 1
        fi
    else
        log INFO "Неблокирующее удаление: подтверждение пропущено (--yes/non-interactive)"
    fi

    if ! validate_destructive_runtime_paths; then
        log ERROR "Операция uninstall заблокирована: обнаружены небезопасные runtime-пути"
        exit 1
    fi

    echo ""
    set +e

    local manage_systemd_uninstall=true
    if ! systemctl_available; then
        manage_systemd_uninstall=false
        log INFO "systemctl не найден; systemd-операции удаления пропущены"
    elif ! systemd_running; then
        manage_systemd_uninstall=false
        log INFO "systemd не запущен; systemd-операции удаления пропущены"
    fi

    log STEP "Останавливаем сервисы..."
    local -a services=(xray xray-health.service xray-health.timer xray-auto-update.service xray-auto-update.timer)
    if [[ "$manage_systemd_uninstall" == true ]]; then
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

    log STEP "Удаляем логи и бэкапы..."
    uninstall_remove_dir "$XRAY_LOGS"
    uninstall_remove_dir "$XRAY_BACKUP"
    uninstall_remove_file "$INSTALL_LOG"
    uninstall_remove_file "$UPDATE_LOG"
    uninstall_remove_file "$DIAG_LOG"
    uninstall_remove_file "$HEALTH_LOG"
    uninstall_remove_file "$SELF_CHECK_STATE_FILE"

    log STEP "Удаляем cron и logrotate..."
    uninstall_remove_file /etc/cron.d/xray-health
    uninstall_remove_file /etc/logrotate.d/xray

    log STEP "Удаляем системные оптимизации..."
    uninstall_remove_file /etc/sysctl.d/99-xray.conf
    uninstall_remove_file /etc/security/limits.d/99-xray.conf
    sysctl --system > /dev/null 2>&1 || true

    log STEP "Удаляем пользователя и группу..."
    if id "$XRAY_USER" > /dev/null 2>&1; then
        userdel -r "$XRAY_USER" 2> /dev/null || userdel "$XRAY_USER" 2> /dev/null || true
        echo -e "  ${GREEN}✅ Удалён пользователь ${XRAY_USER}${NC}"
    fi
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        groupdel "$XRAY_GROUP" 2> /dev/null || true
        echo -e "  ${GREEN}✅ Удалена группа ${XRAY_GROUP}${NC}"
    fi
    uninstall_remove_dir "$XRAY_HOME"

    if [[ "$manage_systemd_uninstall" == true ]]; then
        if systemctl_uninstall_bounded daemon-reload; then
            echo -e "  ${GREEN}✅ systemctl daemon-reload${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Не удалось выполнить systemctl daemon-reload${NC}"
        fi
    fi

    set -e

    local uninstall_done_title uninstall_done_width
    uninstall_done_title="УДАЛЕНИЕ ЗАВЕРШЕНО"
    uninstall_done_width=$(ui_box_width_for_lines 60 90 "$uninstall_done_title")
    echo ""
    echo -e "${BOLD}${GREEN}$(ui_box_border_string top "$uninstall_done_width")${NC}"
    echo -e "${BOLD}${GREEN}$(ui_box_line_string "$uninstall_done_title" "$uninstall_done_width")${NC}"
    echo -e "${BOLD}${GREEN}$(ui_box_border_string bottom "$uninstall_done_width")${NC}"
    echo ""
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
        "$SELF_CHECK_STATE_FILE"
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

status_flow() {
    local status_title status_box_width
    status_title="NETWORK STEALTH CORE - STATUS"
    status_box_width=$(ui_box_width_for_lines 60 90 "$status_title")
    echo ""
    echo -e "${BOLD}${CYAN}$(ui_box_border_string top "$status_box_width")${NC}"
    echo -e "${BOLD}${CYAN}$(ui_box_line_string "$status_title" "$status_box_width")${NC}"
    echo -e "${BOLD}${CYAN}$(ui_box_border_string bottom "$status_box_width")${NC}"
    echo ""

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

    if [[ -f "$XRAY_CONFIG" ]]; then
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
        case "$transport_mode" in
            h2 | http/2) transport_mode="http2" ;;
            grpc | xhttp) ;;
            *) transport_mode="unknown" ;;
        esac
        echo -e "  Transport: ${transport_mode}"
        if [[ "$transport_mode" == "grpc" || "$transport_mode" == "http2" ]]; then
            echo -e "  Режим: legacy transport (рекомендуется xray-reality.sh migrate-stealth)"
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
    fi

    echo -e "${BOLD}Сервер:${NC}"
    local server_ip="${SERVER_IP:-}"
    [[ -n "$server_ip" ]] || server_ip="недоступен (не задан в config.env)"
    echo -e "  IPv4: ${server_ip}"
    local server_ip6="${SERVER_IP6:-}"
    [[ -n "$server_ip6" ]] || server_ip6="недоступен"
    echo -e "  IPv6: ${server_ip6}"
    echo ""

    if [[ -d "$XRAY_KEYS" ]]; then
        echo -e "${BOLD}Клиентские конфиги:${NC}"
        echo -e "  ${XRAY_KEYS}/clients.txt"
        if [[ -d "${XRAY_KEYS}/export" ]]; then
            echo -e "  ${XRAY_KEYS}/export/ (raw xray, capability matrix, client templates)"
        fi
    fi
    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BOLD}${CYAN}$(ui_section_title_string "Подробная информация")${NC}"
        echo ""

        if [[ -f "$XRAY_CONFIG" ]]; then
            echo -e "${BOLD}Детали конфигураций:${NC}"
            local i=0
            local port dest domain sni fp net service
            while IFS=$'\t' read -r port dest sni fp net service; do
                [[ -z "$port" ]] && continue
                i=$((i + 1))
                domain="${dest%%:*}"

                local port_status="${RED}не слушается${NC}"
                if port_is_listening "$port"; then
                    port_status="${GREEN}активен${NC}"
                fi

                local transport_label
                transport_label=$(transport_endpoint_label "$net")

                echo -e "  Config ${i}:"
                echo -e "    Порт:        ${port} (${port_status})"
                echo -e "    Домен:       ${domain:-?}"
                echo -e "    SNI:         ${sni:-?}"
                echo -e "    Fingerprint: ${fp:-?}"
                echo -e "    Transport:   $(transport_display_name "${net:-xhttp}")"
                echo -e "    ${transport_label}: ${service:-?}"
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
                    (.streamSettings.xhttpSettings.path // .streamSettings.grpcSettings.serviceName // .streamSettings.httpSettings.path // "?")
                  ] | @tsv
            ' "$XRAY_CONFIG" 2> /dev/null)
        fi

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

        if declare -F self_check_status_summary_tsv > /dev/null 2>&1; then
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
        fi

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

        echo ""
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
                echo "Логи health check не найдены"
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
                echo "Недоступно"
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
        elif [[ ! "$current_version" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z]+)*$ ]]; then
            echo -e "${YELLOW}Нестандартный формат версии: ${current_version}${NC}"
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
