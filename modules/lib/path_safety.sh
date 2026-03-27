#!/usr/bin/env bash
# shellcheck shell=bash

validate_no_control_chars() {
    local name="$1"
    local value="${2:-}"
    [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" =~ [[:cntrl:]] ]] && {
        log ERROR "${name} содержит управляющие символы"
        return 1
    }
    return 0
}

validate_safe_executable_path() {
    local name="$1"
    local path="${2:-}"
    local resolved

    [[ -n "$path" ]] || {
        log ERROR "${name} не может быть пустым"
        return 1
    }
    validate_no_control_chars "$name" "$path" || return 1

    resolved=$(realpath -m "$path" 2> /dev/null || echo "$path")
    if [[ "$resolved" != /* ]]; then
        log ERROR "${name} должен быть абсолютным путём: ${path}"
        return 1
    fi
    if [[ ! "$resolved" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
        log ERROR "${name} содержит небезопасные символы: ${path}"
        return 1
    fi
    return 0
}

is_valid_systemd_duration() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 1
    [[ "$value" =~ ^[0-9]+(us|ms|s|min|m|h|d|w)?$ ]]
}

is_valid_systemd_oncalendar() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 1
    validate_no_control_chars "AUTO_UPDATE_ONCALENDAR" "$value" || return 1
    [[ "$value" =~ ^[A-Za-z0-9*.,:\/_+\ -]+$ ]]
}

is_dangerous_destructive_path() {
    local path="$1"
    case "$path" in
        "/" | "/bin" | "/boot" | "/dev" | "/etc" | "/home" | "/lib" | "/lib64" | "/media" | "/mnt" | "/opt" | "/proc" | "/root" | "/run" | "/sbin" | "/srv" | "/sys" | "/tmp" | "/usr" | "/usr/local" | "/var" | "/var/backups" | "/var/lib" | "/var/log")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

path_depth() {
    local path="${1#/}"
    if [[ -z "$path" ]]; then
        echo 0
        return 0
    fi
    awk -F/ '{print NF}' <<< "$path"
}

validate_destructive_path_guard() {
    local name="$1"
    local path="${2:-}"
    local resolved
    local depth

    if [[ -z "$path" ]]; then
        log ERROR "${name} не может быть пустым"
        return 1
    fi
    if ! validate_no_control_chars "$name" "$path"; then
        return 1
    fi

    resolved=$(realpath -m "$path" 2> /dev/null || echo "$path")
    if [[ "$resolved" != /* ]]; then
        log ERROR "${name} должен быть абсолютным путём: ${path}"
        return 1
    fi
    if is_dangerous_destructive_path "$resolved"; then
        log ERROR "${name} указывает на опасный путь: ${resolved}"
        return 1
    fi

    depth=$(path_depth "$resolved")
    if ((depth < 2)); then
        log ERROR "${name} слишком общий путь для destructive-операций: ${resolved}"
        return 1
    fi

    return 0
}

path_has_project_scope_marker() {
    if declare -F managed_path_has_project_segment > /dev/null 2>&1; then
        managed_path_has_project_segment "$1"
        return $?
    fi
    local path_lc="${1,,}"
    [[ "$path_lc" =~ (^|/)(xray|xray-reality|network-stealth-core)(/|$) ]]
}

is_sensitive_system_path_prefix() {
    local path="${1:-}"
    case "$path" in
        /etc/* | /usr/* | /var/* | /opt/* | /root/* | /home/* | /boot/* | /lib/* | /lib64/* | /sbin/* | /bin/* | /run/* | /proc/* | /sys/* | /dev/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

path_matches_any_parent() {
    local path="${1:-}"
    shift
    local resolved_path resolved_parent candidate resolved_candidate
    resolved_path=$(realpath -m "$path" 2> /dev/null || echo "$path")
    resolved_parent=$(dirname "$resolved_path")
    for candidate in "$@"; do
        [[ -n "$candidate" ]] || continue
        resolved_candidate=$(realpath -m "$candidate" 2> /dev/null || echo "$candidate")
        if [[ "$resolved_parent" == "$resolved_candidate" ]]; then
            return 0
        fi
    done
    return 1
}

validate_destructive_path_scope() {
    local name="$1"
    local path="$2"
    local resolved
    local base

    resolved=$(realpath -m "$path" 2> /dev/null || echo "$path")

    case "$name" in
        XRAY_KEYS | XRAY_BACKUP | XRAY_LOGS | XRAY_HOME | XRAY_DATA_DIR)
            if is_sensitive_system_path_prefix "$resolved" && ! path_has_project_scope_marker "$resolved"; then
                log ERROR "${name} в системном каталоге должен указывать на отдельный путь проекта (ожидается сегмент xray, xray-reality или network-stealth-core): ${resolved}"
                return 1
            fi
            ;;
        XRAY_GEO_DIR)
            if path_has_project_scope_marker "$resolved"; then
                return 0
            fi
            local xray_bin_dir
            xray_bin_dir=$(dirname "${XRAY_BIN:-}")
            xray_bin_dir=$(realpath -m "$xray_bin_dir" 2> /dev/null || echo "$xray_bin_dir")
            if [[ -n "${XRAY_BIN:-}" && "$(basename "${XRAY_BIN}")" == "xray" && "$resolved" == "$xray_bin_dir" ]]; then
                return 0
            fi
            if is_sensitive_system_path_prefix "$resolved"; then
                log ERROR "XRAY_GEO_DIR в системном каталоге должен указывать на путь проекта (xray, xray-reality или network-stealth-core) или dirname(XRAY_BIN) (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_BIN)
            base=$(basename "$resolved")
            if [[ "$base" != "xray" ]]; then
                log ERROR "XRAY_BIN должен указывать на бинарник xray (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/usr/local/bin" "/opt/xray/bin"; then
                return 0
            fi
            log ERROR "XRAY_BIN должен указывать на managed xray binary path (получено: ${resolved})"
            return 1
            ;;
        XRAY_SCRIPT_PATH)
            base=$(basename "$resolved")
            if [[ "$base" != "xray-reality.sh" ]]; then
                log ERROR "XRAY_SCRIPT_PATH должен указывать на xray-reality.sh (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/usr/local/bin" "/opt/xray/bin"; then
                return 0
            fi
            log ERROR "XRAY_SCRIPT_PATH должен указывать на managed wrapper path (получено: ${resolved})"
            return 1
            ;;
        XRAY_UPDATE_SCRIPT)
            base=$(basename "$resolved")
            if [[ "$base" != "xray-reality-update.sh" ]]; then
                log ERROR "XRAY_UPDATE_SCRIPT должен указывать на xray-reality-update.sh (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/usr/local/bin" "/opt/xray/bin"; then
                return 0
            fi
            log ERROR "XRAY_UPDATE_SCRIPT должен указывать на managed update-wrapper path (получено: ${resolved})"
            return 1
            ;;
        XRAY_CONFIG)
            base=$(basename "$resolved")
            if [[ "$base" != "config.json" ]]; then
                log ERROR "XRAY_CONFIG должен указывать на config.json (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/etc/xray" "/opt/xray/etc"; then
                return 0
            fi
            log ERROR "XRAY_CONFIG должен указывать на managed config path (получено: ${resolved})"
            return 1
            ;;
        XRAY_ENV)
            base=$(basename "$resolved")
            if [[ "$base" != "config.env" ]]; then
                log ERROR "XRAY_ENV должен указывать на config.env (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/etc/xray-reality" "/opt/xray/etc"; then
                return 0
            fi
            log ERROR "XRAY_ENV должен указывать на managed env path (получено: ${resolved})"
            return 1
            ;;
        XRAY_POLICY)
            base=$(basename "$resolved")
            if [[ "$base" != "policy.json" ]]; then
                log ERROR "XRAY_POLICY должен указывать на policy.json (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/etc/xray-reality" "/opt/xray/etc"; then
                return 0
            fi
            log ERROR "XRAY_POLICY должен указывать на managed policy path (получено: ${resolved})"
            return 1
            ;;
        XRAY_MANAGED_CUSTOM_DOMAINS_FILE)
            base=$(basename "$resolved")
            if [[ "$base" != "custom-domains.txt" ]]; then
                log ERROR "XRAY_MANAGED_CUSTOM_DOMAINS_FILE должен указывать на custom-domains.txt (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/etc/xray-reality" "/opt/xray/etc"; then
                return 0
            fi
            log ERROR "XRAY_MANAGED_CUSTOM_DOMAINS_FILE должен указывать на managed custom-domains path (получено: ${resolved})"
            return 1
            ;;
        MINISIGN_KEY)
            base=$(basename "$resolved")
            if [[ "$base" != "minisign.pub" ]]; then
                log ERROR "MINISIGN_KEY должен указывать на minisign.pub (получено: ${resolved})"
                return 1
            fi
            if ! is_sensitive_system_path_prefix "$resolved"; then
                return 0
            fi
            if path_has_project_scope_marker "$resolved" || path_matches_any_parent "$resolved" "/etc/xray" "/opt/xray/etc"; then
                return 0
            fi
            log ERROR "MINISIGN_KEY должен указывать на managed minisign key path (получено: ${resolved})"
            return 1
            ;;
        *) ;;
    esac

    if is_sensitive_system_path_prefix "$resolved" && ! path_has_project_scope_marker "$resolved"; then
        log ERROR "${name} в системном каталоге должен указывать на путь проекта (ожидается сегмент xray, xray-reality или network-stealth-core): ${resolved}"
        return 1
    fi

    return 0
}

validate_destructive_runtime_paths() {
    local var value dir
    local -a destructive_dirs=(
        XRAY_KEYS XRAY_BACKUP XRAY_LOGS XRAY_HOME XRAY_DATA_DIR XRAY_GEO_DIR MEASUREMENTS_DIR
    )
    local -a destructive_files=(
        XRAY_BIN XRAY_CONFIG XRAY_ENV XRAY_POLICY XRAY_MANAGED_CUSTOM_DOMAINS_FILE XRAY_SCRIPT_PATH XRAY_UPDATE_SCRIPT MINISIGN_KEY SELF_CHECK_STATE_FILE SELF_CHECK_HISTORY_FILE MEASUREMENTS_SUMMARY_FILE MEASUREMENTS_ROTATION_STATE_FILE
    )

    for var in "${destructive_dirs[@]}"; do
        value="${!var:-}"
        [[ -z "$value" ]] && continue
        validate_destructive_path_guard "$var" "$value" || return 1
        validate_destructive_path_scope "$var" "$value" || return 1
    done

    for var in "${destructive_files[@]}"; do
        value="${!var:-}"
        [[ -n "$value" ]] || continue
        if ! validate_no_control_chars "$var" "$value"; then
            return 1
        fi
        validate_destructive_path_scope "$var" "$value" || return 1
        dir=$(dirname "$value")
        validate_destructive_path_guard "${var} (dirname)" "$dir" || return 1
    done

    return 0
}

validate_mirror_list_urls() {
    local list="$1"
    local label="$2"
    local item

    while read -r item; do
        item=$(trim_ws "$item")
        [[ -z "$item" ]] && continue
        if ! is_valid_https_url "$item"; then
            log ERROR "${label}: невалидный URL: ${item}"
            return 1
        fi
    done < <(split_list "$list")
    return 0
}
