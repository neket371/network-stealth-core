#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

BACKUP_STACK=()
declare -A LOCAL_BACKUP_MAP=()
BACKUP_SESSION_DIR=""
RUNTIME_RESTORE_RESUME_XRAY=false
RUNTIME_RESTORE_RESUME_HEALTH_TIMER=false
RUNTIME_RESTORE_RESUME_AUTO_UPDATE_TIMER=false

capture_failure_proof() {
    local proof_dir="${XRAY_FAILURE_PROOF_DIR:-}"
    [[ -n "$proof_dir" ]] || return 0

    mkdir -p "$proof_dir" 2> /dev/null || return 0

    {
        printf 'action=%s\n' "${ACTION:-unknown}"
        printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'script_version=%s\n' "${SCRIPT_VERSION:-unknown}"
        printf 'xray_user=%s\n' "${XRAY_USER:-xray}"
        printf 'xray_group=%s\n' "${XRAY_GROUP:-xray}"
        printf 'xray_logs=%s\n' "${XRAY_LOGS:-/var/log/xray}"
        printf 'xray_bin=%s\n' "${XRAY_BIN:-/usr/local/bin/xray}"
        printf 'xray_config=%s\n' "${XRAY_CONFIG:-/etc/xray/config.json}"
    } > "${proof_dir}/meta.env" 2> /dev/null || true

    if command -v systemctl > /dev/null 2>&1; then
        systemctl cat xray > "${proof_dir}/systemctl-cat-xray.txt" 2>&1 || true
        systemctl show xray \
            -p User \
            -p Group \
            -p SupplementaryGroups \
            -p LogsDirectory \
            -p ReadWritePaths \
            -p FragmentPath \
            -p DropInPaths \
            -p MainPID \
            > "${proof_dir}/systemctl-show-xray.txt" 2>&1 || true
        systemctl status xray --no-pager -l > "${proof_dir}/systemctl-status-xray.txt" 2>&1 || true
        journalctl -u xray --no-pager -n 200 > "${proof_dir}/journal-xray.txt" 2>&1 || true
        journalctl -u xray-health --no-pager -n 200 > "${proof_dir}/journal-xray-health.txt" 2>&1 || true
    fi

    id "${XRAY_USER:-xray}" > "${proof_dir}/id-xray.txt" 2>&1 || true
    getent passwd "${XRAY_USER:-xray}" > "${proof_dir}/getent-passwd-xray.txt" 2>&1 || true
    getent group "${XRAY_GROUP:-xray}" > "${proof_dir}/getent-group-xray.txt" 2>&1 || true
    getent group syslog > "${proof_dir}/getent-group-syslog.txt" 2>&1 || true
    namei -l "${XRAY_LOGS:-/var/log/xray}/access.log" > "${proof_dir}/namei-access-log.txt" 2>&1 || true
    stat -c '%U:%G:%a %n' \
        /var/log \
        "${XRAY_LOGS:-/var/log/xray}" \
        "${XRAY_LOGS:-/var/log/xray}/access.log" \
        "${XRAY_LOGS:-/var/log/xray}/error.log" \
        > "${proof_dir}/log-path-stats.txt" 2>&1 || true

    if [[ -f /etc/systemd/system/xray.service ]]; then
        cp -a /etc/systemd/system/xray.service "${proof_dir}/xray.service" 2> /dev/null || true
    fi
    if [[ -f /etc/logrotate.d/xray ]]; then
        cp -a /etc/logrotate.d/xray "${proof_dir}/logrotate-xray.conf" 2> /dev/null || true
    fi
}

ensure_backup_session() {
    if [[ -z "$BACKUP_SESSION_DIR" ]]; then
        mkdir -p "$XRAY_BACKUP"
        local ts
        ts=$(date '+%Y%m%d-%H%M%S')
        local unique_suffix
        unique_suffix="${$}-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
        BACKUP_SESSION_DIR="${XRAY_BACKUP}/${ts}-${unique_suffix}"
        if ! mkdir "$BACKUP_SESSION_DIR" 2> /dev/null; then
            BACKUP_SESSION_DIR=$(mktemp -d "${XRAY_BACKUP}/${ts}-XXXXXX")
        fi
    fi
}

rotate_backups() {
    [[ -d "$XRAY_BACKUP" ]] || return 0
    local max_backups="${MAX_BACKUPS:-10}"
    if [[ ! "$max_backups" =~ ^[0-9]+$ ]] || ((max_backups < 1 || max_backups > 1000)); then
        max_backups=10
    fi
    local to_delete
    to_delete=$(find "$XRAY_BACKUP" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\n' |
        sort -nr |
        tail -n +"$((max_backups + 1))" |
        cut -f2-) || true
    if [[ -n "$to_delete" ]]; then
        while IFS= read -r dir; do
            rm -rf "$dir"
        done <<< "$to_delete"
    fi
}

backup_file() {
    local target="$1"
    if [[ ! -e "$target" ]]; then
        record_created_path "$target"
        return 0
    fi
    if [[ -f "$target" ]]; then
        ensure_backup_session
        if [[ ! -f "${BACKUP_SESSION_DIR}${target}" ]]; then
            mkdir -p "${BACKUP_SESSION_DIR}$(dirname "$target")"
            cp -a "$target" "${BACKUP_SESSION_DIR}${target}"
            BACKUP_STACK+=("$target")
            log INFO "Сохранён бэкап: ${BACKUP_SESSION_DIR}${target}"
        fi
        if [[ "$KEEP_LOCAL_BACKUPS" == true ]] && [[ ! -f "${target}.backup" ]]; then
            cp -a "$target" "${target}.backup"
            LOCAL_BACKUP_MAP["$target"]=1
            log INFO "Создан бэкап: ${target}.backup"
        fi
    fi
}

is_runtime_critical_path() {
    local path="${1:-}"
    case "$path" in
        "$XRAY_CONFIG" | /etc/xray/* | "$XRAY_BIN" | /usr/local/bin/xray | /etc/systemd/system/xray.service | /etc/systemd/system/xray*.service | /etc/systemd/system/xray*.timer)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

systemctl_unit_loaded() {
    local unit="${1:-}"
    [[ -n "$unit" ]] || return 1
    [[ "$(systemctl show "$unit" -p LoadState --value 2> /dev/null || true)" == "loaded" ]]
}

wait_for_xray_process_exit() {
    local attempts=50
    local delay_s=0.2
    local try
    for ((try = 0; try < attempts; try++)); do
        if ! pgrep -x xray > /dev/null 2>&1; then
            return 0
        fi
        sleep "$delay_s"
    done
    return 1
}

cleanup_empty_runtime_dirs() {
    local -a dirs=(
        "${XRAY_KEYS:-/etc/xray/private/keys}"
        "$(dirname "${XRAY_KEYS:-/etc/xray/private/keys}")"
        "$(dirname "${XRAY_CONFIG:-/etc/xray/config.json}")"
        "${XRAY_HOME:-/var/lib/xray}/measurements"
        "${XRAY_HOME:-/var/lib/xray}"
        "${XRAY_LOGS:-/var/log/xray}"
        "${XRAY_BACKUP:-/var/backups/xray}"
        "$(dirname "${XRAY_ENV:-/etc/xray-reality/config.env}")"
    )
    local dir
    for dir in "${dirs[@]}"; do
        [[ -n "$dir" && "$dir" == /* ]] || continue
        rmdir "$dir" 2> /dev/null || true
    done
}

runtime_quiesce_for_restore() {
    if ! systemd_running; then
        return 0
    fi

    if systemctl_unit_loaded xray-health.timer && systemctl is-active --quiet xray-health.timer 2> /dev/null; then
        RUNTIME_RESTORE_RESUME_HEALTH_TIMER=true
        if ! systemctl_uninstall_bounded stop xray-health.timer; then
            log WARN "Не удалось остановить xray-health.timer перед восстановлением"
        fi
    fi

    if systemctl_unit_loaded xray-auto-update.timer && systemctl is-active --quiet xray-auto-update.timer 2> /dev/null; then
        RUNTIME_RESTORE_RESUME_AUTO_UPDATE_TIMER=true
        if ! systemctl_uninstall_bounded stop xray-auto-update.timer; then
            log WARN "Не удалось остановить xray-auto-update.timer перед восстановлением"
        fi
    fi

    if systemctl_unit_loaded xray-health.service && systemctl is-active --quiet xray-health.service 2> /dev/null; then
        if ! systemctl_uninstall_bounded stop xray-health.service; then
            log WARN "Не удалось остановить xray-health.service перед восстановлением"
        fi
    fi

    if systemctl_unit_loaded xray-auto-update.service && systemctl is-active --quiet xray-auto-update.service 2> /dev/null; then
        if ! systemctl_uninstall_bounded stop xray-auto-update.service; then
            log WARN "Не удалось остановить xray-auto-update.service перед восстановлением"
        fi
    fi

    if systemctl_unit_loaded xray.service && systemctl is-active --quiet xray 2> /dev/null; then
        RUNTIME_RESTORE_RESUME_XRAY=true
        if ! systemctl_uninstall_bounded stop xray; then
            log WARN "Не удалось остановить xray перед восстановлением"
        fi
    fi

    if ! wait_for_xray_process_exit; then
        log WARN "Процессы xray ещё видны после stop; продолжаем через atomic restore"
    fi
}

restore_file_from_snapshot() {
    local source_path="$1"
    local dest_path="$2"
    local dest_dir tmp_path

    dest_dir="$(dirname "$dest_path")"
    mkdir -p "$dest_dir"
    tmp_path="$(mktemp "${dest_dir}/.$(basename "$dest_path").restore.XXXXXX")"
    if ! cp -a "$source_path" "$tmp_path"; then
        rm -f "$tmp_path"
        return 1
    fi
    if ! mv -f "$tmp_path" "$dest_path"; then
        rm -f "$tmp_path"
        return 1
    fi
    return 0
}

reconcile_runtime_after_restore() {
    if ! systemctl_available || ! systemd_running; then
        return 0
    fi

    local need_reconcile=false
    local path
    for path in "${BACKUP_STACK[@]}"; do
        if is_runtime_critical_path "$path"; then
            need_reconcile=true
            break
        fi
    done
    if [[ "$need_reconcile" != true ]]; then
        for path in "${CREATED_PATHS[@]}"; do
            if is_runtime_critical_path "$path"; then
                need_reconcile=true
                break
            fi
        done
    fi
    if [[ "$need_reconcile" != true ]]; then
        if [[ "$RUNTIME_RESTORE_RESUME_XRAY" == true || "$RUNTIME_RESTORE_RESUME_HEALTH_TIMER" == true || "$RUNTIME_RESTORE_RESUME_AUTO_UPDATE_TIMER" == true ]]; then
            need_reconcile=true
        fi
    fi
    if [[ "$need_reconcile" != true ]]; then
        return 0
    fi

    log WARN "Синхронизируем runtime после отката файлов..."
    if ! systemctl_run_bounded daemon-reload; then
        log WARN "Не удалось выполнить systemctl daemon-reload после rollback"
    fi

    if systemctl_unit_loaded xray.service; then
        if [[ ! -x "$XRAY_BIN" || ! -f "$XRAY_CONFIG" ]]; then
            log WARN "Пропускаем restart xray после rollback: бинарник или конфиг отсутствуют"
        elif ! "$XRAY_BIN" -test -c "$XRAY_CONFIG" > /dev/null 2>&1; then
            log WARN "Пропускаем restart xray после rollback: восстановленный конфиг не прошёл xray -test"
        elif declare -F systemctl_restart_xray_bounded > /dev/null; then
            if systemctl_restart_xray_bounded; then
                log INFO "Runtime синхронизирован: xray перезапущен после rollback"
            else
                log WARN "Не удалось перезапустить xray после rollback"
            fi
        else
            log WARN "Пропускаем restart xray после rollback: helper systemctl_restart_xray_bounded недоступен"
        fi
    fi

    if [[ "$RUNTIME_RESTORE_RESUME_HEALTH_TIMER" == true ]] && systemctl_unit_loaded xray-health.timer; then
        if ! systemctl_run_bounded start xray-health.timer; then
            log WARN "Не удалось заново запустить xray-health.timer после rollback"
        fi
    fi

    if [[ "$RUNTIME_RESTORE_RESUME_AUTO_UPDATE_TIMER" == true ]] && systemctl_unit_loaded xray-auto-update.timer; then
        if ! systemctl_run_bounded start xray-auto-update.timer; then
            log WARN "Не удалось заново запустить xray-auto-update.timer после rollback"
        fi
    fi

    RUNTIME_RESTORE_RESUME_XRAY=false
    RUNTIME_RESTORE_RESUME_HEALTH_TIMER=false
    RUNTIME_RESTORE_RESUME_AUTO_UPDATE_TIMER=false
}

cleanup_on_error() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log ERROR "Операция прервана с ошибкой (код: ${exit_code})"
        capture_failure_proof || true

        if [[ ${#FIREWALL_ROLLBACK_ENTRIES[@]} -gt 0 ]]; then
            rollback_firewall_changes || true
        fi

        local need_runtime_quiesce=false
        local restore_candidate
        for restore_candidate in "${BACKUP_STACK[@]}"; do
            if is_runtime_critical_path "$restore_candidate"; then
                need_runtime_quiesce=true
                break
            fi
        done
        if [[ "$need_runtime_quiesce" != true ]]; then
            for restore_candidate in "${CREATED_PATHS[@]}"; do
                if is_runtime_critical_path "$restore_candidate"; then
                    need_runtime_quiesce=true
                    break
                fi
            done
        fi
        if [[ "$need_runtime_quiesce" == true ]]; then
            runtime_quiesce_for_restore || true
        fi

        if [[ ${#BACKUP_STACK[@]} -gt 0 ]]; then
            log WARN "Откатываем изменения..."
            local _i
            for ((_i = ${#BACKUP_STACK[@]} - 1; _i >= 0; _i--)); do
                local backup="${BACKUP_STACK[$_i]}"
                local restored=false
                if [[ -n "${LOCAL_BACKUP_MAP[$backup]:-}" ]] && [[ -f "${backup}.backup" ]]; then
                    mv "${backup}.backup" "$backup"
                    restored=true
                    log INFO "Восстановлен: $backup"
                elif [[ -n "$BACKUP_SESSION_DIR" ]] && [[ -f "${BACKUP_SESSION_DIR}${backup}" ]]; then
                    if restore_file_from_snapshot "${BACKUP_SESSION_DIR}${backup}" "$backup"; then
                        restored=true
                        log INFO "Восстановлен из сессии: $backup"
                    fi
                fi
                [[ "$restored" == true ]] || log WARN "Нет бэкапа для: $backup"
            done
        fi

        if [[ ${#CREATED_PATHS[@]} -gt 0 ]]; then
            log WARN "Удаляем новые файлы, созданные в неуспешной сессии..."
            local _j created_path
            for ((_j = ${#CREATED_PATHS[@]} - 1; _j >= 0; _j--)); do
                created_path="${CREATED_PATHS[$_j]}"
                [[ -n "$created_path" ]] || continue
                if [[ -f "$created_path" || -L "$created_path" ]]; then
                    rm -f "$created_path"
                    log INFO "Удалён созданный файл: $created_path"
                elif [[ -d "$created_path" ]]; then
                    rm -rf "$created_path"
                    log INFO "Удалена созданная директория: $created_path"
                fi
            done
        fi

        cleanup_empty_runtime_dirs || true

        reconcile_runtime_after_restore || true

        log INFO "Лог ошибок: $INSTALL_LOG"
        if command -v sync > /dev/null 2>&1; then
            sync > /dev/null 2>&1 || true
        fi
        if declare -F cleanup_logging_processes > /dev/null; then
            cleanup_logging_processes || true
        fi
        exit "$exit_code"
    else
        if [[ ${#LOCAL_BACKUP_MAP[@]} -gt 0 ]]; then
            log INFO "Очистка временных бэкапов..."
            local backup
            for backup in "${!LOCAL_BACKUP_MAP[@]}"; do
                rm -f "${backup}.backup"
            done
        fi
        if [[ -n "$BACKUP_SESSION_DIR" ]]; then
            log INFO "Сохранён бэкап: ${BACKUP_SESSION_DIR}"
            rotate_backups
        fi
        FIREWALL_ROLLBACK_ENTRIES=()
        FIREWALL_FIREWALLD_DIRTY=false
        CREATED_PATHS=()
        CREATED_PATH_SET=()
        if declare -F cleanup_logging_processes > /dev/null; then
            cleanup_logging_processes || true
        fi
    fi
}

trap cleanup_on_error EXIT
