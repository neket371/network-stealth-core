#!/usr/bin/env bash
# shellcheck shell=bash

: "${XRAY_SYSTEMCTL_UNINSTALL_TIMEOUT:=30}"
: "${SCRIPT_VERSION:=}"
: "${XRAY_USER:=xray}"
: "${XRAY_GROUP:=xray}"
: "${XRAY_LOGS:=/var/log/xray}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_CONFIG:=/etc/xray/config.json}"
: "${XRAY_HOME:=/var/lib/xray}"
: "${XRAY_KEYS:=/etc/xray/private/keys}"
: "${XRAY_BACKUP:=/var/backups/xray}"
: "${XRAY_SERVICE:=xray}"
: "${SYSTEMD_MANAGEMENT_DISABLED:=false}"
: "${XRAY_SCRIPT_PATH:=/usr/local/bin/xray-reality.sh}"
: "${SELF_CHECK_STATE_FILE:=/var/lib/xray/self-check.json}"
: "${AUTO_ROLLBACK:=true}"
: "${HAS_IPV6:=false}"

if ! declare -p PORTS > /dev/null 2>&1; then PORTS=(); fi
if ! declare -p PORTS_V6 > /dev/null 2>&1; then PORTS_V6=(); fi

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

mode_digit_allows_execute() {
    local digit="${1:-0}"
    [[ "$digit" =~ ^[0-7]$ ]] || return 1
    (((8#${digit} & 1) != 0))
}

systemd_log_supplementary_groups() {
    local logs_path="${1:-/var/log/xray}"
    local primary_user="${2:-$XRAY_USER}"
    local primary_group="${3:-$XRAY_GROUP}"
    local target_dir
    target_dir=$(dirname "${logs_path%/}")
    [[ -n "$target_dir" && "$target_dir" == /* ]] || return 0

    local current=""
    local rel_path="${target_dir#/}"
    local -a components=()
    IFS='/' read -r -a components <<< "$rel_path"

    local -a required_groups=()
    declare -A seen_groups=()
    local component stats owner group mode user_digit group_digit other_digit
    local preserve_var_log_parent_group=false
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        current="${current}/${component}"

        stats=$(stat -c '%U:%G:%a' "$current" 2> /dev/null) || return 0
        IFS=':' read -r owner group mode <<< "$stats"
        mode="${mode: -3}"
        user_digit="${mode:0:1}"
        group_digit="${mode:1:1}"
        other_digit="${mode:2:1}"

        if [[ "$owner" == "$primary_user" ]] && mode_digit_allows_execute "$user_digit"; then
            continue
        fi
        if [[ "$group" == "$primary_group" ]] && mode_digit_allows_execute "$group_digit"; then
            continue
        fi
        preserve_var_log_parent_group=false
        if [[ "$logs_path" == /var/log/* && "$current" == "/var/log" && "$group" != "root" ]]; then
            preserve_var_log_parent_group=true
        fi
        if mode_digit_allows_execute "$other_digit" && [[ "$preserve_var_log_parent_group" != true ]]; then
            continue
        fi
        if ! mode_digit_allows_execute "$group_digit"; then
            continue
        fi
        if ! validate_systemd_user_group_value "$group" "логового group-parent"; then
            continue
        fi
        if [[ -z "${seen_groups[$group]:-}" ]]; then
            seen_groups["$group"]=1
            required_groups+=("$group")
        fi
    done

    ((${#required_groups[@]} > 0)) || return 0
    printf '%s\n' "${required_groups[*]}"
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

ensure_xray_runtime_logs_ready() {
    local logs_dir="${XRAY_LOGS%/}"
    [[ -n "$logs_dir" ]] || logs_dir="/var/log/xray"

    if [[ ! -d "$logs_dir" ]] && declare -F record_created_path > /dev/null 2>&1; then
        record_created_path "$logs_dir"
    fi
    install -d -m 0750 -o "$XRAY_USER" -g "$XRAY_GROUP" "$logs_dir"
    chown "${XRAY_USER}:${XRAY_GROUP}" "$logs_dir"
    chmod 750 "$logs_dir"

    local log_file
    for log_file in "$logs_dir/access.log" "$logs_dir/error.log"; do
        if [[ ! -e "$log_file" ]]; then
            if declare -F record_created_path > /dev/null 2>&1; then
                record_created_path "$log_file"
            fi
            install -m 0640 -o "$XRAY_USER" -g "$XRAY_GROUP" /dev/null "$log_file"
            continue
        fi
        chown "${XRAY_USER}:${XRAY_GROUP}" "$log_file"
        chmod 640 "$log_file"
    done
}

systemd_log_access_directives() {
    local logs_path="${1:-/var/log/xray}"
    local primary_user="${2:-$XRAY_USER}"
    local primary_group="${3:-$XRAY_GROUP}"
    local supplementary_groups=""

    supplementary_groups="$(systemd_log_supplementary_groups "$logs_path" "$primary_user" "$primary_group")"
    if [[ -n "$supplementary_groups" ]]; then
        printf 'SupplementaryGroups=%s\n' "$supplementary_groups"
    fi

    if [[ "$logs_path" == "/var/log/xray" ]]; then
        cat << 'EOF'
LogsDirectory=xray
LogsDirectoryMode=0750
EOF
        return 0
    fi

    printf 'ReadWritePaths=%s\n' "$logs_path"
}

systemctl_uninstall_bounded() {
    local action="$1"
    shift
    local -a units=("$@")
    local timeout_s="${XRAY_SYSTEMCTL_UNINSTALL_TIMEOUT:-30}"
    if [[ ! "$timeout_s" =~ ^[0-9]+$ ]] || ((timeout_s < 5 || timeout_s > 300)); then
        timeout_s=30
    fi

    local cmd_desc="systemctl ${action}"
    if ((${#units[@]} > 0)); then
        cmd_desc+=" ${units[*]}"
    fi

    local rc=0
    local err=""
    if command -v timeout > /dev/null 2>&1; then
        if ((${#units[@]} > 0)); then
            err=$(timeout --signal=TERM --kill-after=10s "${timeout_s}s" systemctl "$action" "${units[@]}" 2>&1) || rc=$?
        else
            err=$(timeout --signal=TERM --kill-after=10s "${timeout_s}s" systemctl "$action" 2>&1) || rc=$?
        fi
        if ((rc == 124 || rc == 137)); then
            log WARN "${cmd_desc} превысил таймаут ${timeout_s}s; продолжаем удаление"
            debug_file "${cmd_desc} timeout (${timeout_s}s): ${err}"
            return "$rc"
        fi
    else
        if ((${#units[@]} > 0)); then
            err=$(systemctl "$action" "${units[@]}" 2>&1) || rc=$?
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

create_systemd_service_manage_mode() {
    local out_manage_systemd_name="$1"
    printf -v "$out_manage_systemd_name" '%s' true
    if ! systemctl_available; then
        log WARN "systemctl не найден; сервис будет создан без активации"
        printf -v "$out_manage_systemd_name" '%s' false
    elif ! systemd_running; then
        log WARN "systemd не запущен; сервис будет создан без активации"
        printf -v "$out_manage_systemd_name" '%s' false
    fi
}

create_systemd_service_ensure_unit_dir() {
    local systemd_dir="/etc/systemd/system"
    if [[ ! -d "$systemd_dir" ]]; then
        if ! install -d -m 755 "$systemd_dir" 2> /dev/null; then
            if [[ "${1:-true}" == true ]]; then
                log ERROR "Не удалось создать каталог ${systemd_dir} для unit-файлов"
                return 1
            fi
            log WARN "Каталог ${systemd_dir} недоступен; создание unit-файла пропущено"
            return 2
        fi
    fi
    return 0
}

create_systemd_service_prepare_values() {
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_user="$1"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_group="$2"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_logs="$3"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_bin="$4"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_config="$5"
    local out_log_directives_name="$6"

    sanitize_systemd_value_into out_user "$XRAY_USER"
    sanitize_systemd_value_into out_group "$XRAY_GROUP"
    sanitize_systemd_value_into out_logs "$XRAY_LOGS"
    sanitize_systemd_value_into out_bin "$XRAY_BIN"
    sanitize_systemd_value_into out_config "$XRAY_CONFIG"
    validate_systemd_user_group_value "$out_user" "XRAY_USER" || return 1
    validate_systemd_user_group_value "$out_group" "XRAY_GROUP" || return 1
    validate_systemd_path_value "$out_logs" "XRAY_LOGS" || return 1
    validate_systemd_path_value "$out_bin" "XRAY_BIN" || return 1
    validate_systemd_path_value "$out_config" "XRAY_CONFIG" || return 1
    printf -v "$out_log_directives_name" '%s' "$(systemd_log_access_directives "$out_logs" "$out_user" "$out_group")"
}

create_systemd_service_write_unit() {
    local service_user="$1"
    local service_group="$2"
    local service_bin="$3"
    local service_config="$4"
    local service_log_directives="$5"

    cleanup_conflicting_xray_service_dropins || return 1

    ensure_xray_runtime_logs_ready || {
        log ERROR "Не удалось подготовить runtime-логи Xray"
        return 1
    }

    backup_file /etc/systemd/system/xray.service
    atomic_write /etc/systemd/system/xray.service 0644 << EOF
[Unit]
Description=Xray Service (Network Stealth Core ${SCRIPT_VERSION})
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
OnFailure=xray-diagnose@%n.service

[Service]
Type=simple
User=${service_user}
Group=${service_group}
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
UMask=0027
${service_log_directives}
ExecStart=${service_bin} run -config ${service_config}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
}

create_systemd_service_activate_unit() {
    local manage_systemd="$1"
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
            local xray_enable_link=""
            local xray_enable_link_missing=false
            if xray_enable_link=$(systemd_enable_symlink_path_for_unit xray.service 2> /dev/null); then
                if [[ ! -e "$xray_enable_link" && ! -L "$xray_enable_link" ]]; then
                    xray_enable_link_missing=true
                fi
            fi
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
            elif [[ "$xray_enable_link_missing" == true && -n "$xray_enable_link" ]] && declare -F record_created_path_literal > /dev/null 2>&1; then
                if [[ -e "$xray_enable_link" || -L "$xray_enable_link" ]]; then
                    record_created_path_literal "$xray_enable_link"
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

create_systemd_service() {
    log STEP "Создаём systemd сервис..."

    local manage_systemd
    create_systemd_service_manage_mode manage_systemd

    local ensure_unit_dir_rc=0
    create_systemd_service_ensure_unit_dir "$manage_systemd" || ensure_unit_dir_rc=$?
    if ((ensure_unit_dir_rc == 2)); then
        return 0
    elif ((ensure_unit_dir_rc != 0)); then
        return 1
    fi

    local _sd_user _sd_group _sd_logs _sd_bin _sd_config _sd_log_directives
    create_systemd_service_prepare_values _sd_user _sd_group _sd_logs _sd_bin _sd_config _sd_log_directives || return 1
    create_systemd_service_write_unit "$_sd_user" "$_sd_group" "$_sd_bin" "$_sd_config" "$_sd_log_directives" || return 1
    create_systemd_service_activate_unit "$manage_systemd"
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

    ensure_xray_runtime_logs_ready || {
        log ERROR "Не удалось подготовить runtime-логи Xray перед запуском"
        return 1
    }

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
    if declare -F refresh_geo_assets > /dev/null 2>&1; then
        if ! refresh_geo_assets; then
            log ERROR "Не удалось обновить GeoIP/GeoSite после обновления Xray"
            exit 1
        fi
    fi

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
