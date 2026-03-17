#!/usr/bin/env bash
# shellcheck shell=bash

: "${SYSTEMD_MANAGEMENT_DISABLED:=false}"
: "${XRAY_SYSTEMCTL_OP_TIMEOUT:=60}"
: "${XRAY_SYSTEMCTL_RESTART_TIMEOUT:=120}"

port_is_listening() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        if ss -H -ltn "sport = :$port" 2> /dev/null | grep -q .; then
            return 0
        fi
        return 1
    fi
    if command -v netstat > /dev/null 2>&1; then
        if netstat -ltn 2> /dev/null | awk -v p=":$port" '$4 ~ p "$"' | grep -q .; then
            return 0
        fi
        return 1
    fi
    if command -v lsof > /dev/null 2>&1; then
        if lsof -iTCP:"$port" -sTCP:LISTEN > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi
    return 1
}

systemctl_available() {
    command -v systemctl > /dev/null 2>&1
}

systemctl_run_bounded() {
    local out_err_var=""
    if [[ $# -ge 2 && "$1" == "--err-var" ]]; then
        out_err_var="$2"
        shift 2
    fi

    local op_timeout="${XRAY_SYSTEMCTL_OP_TIMEOUT:-60}"
    if [[ ! "$op_timeout" =~ ^[0-9]+$ ]] || ((op_timeout < 5 || op_timeout > 600)); then
        op_timeout=60
    fi

    local cmd_desc="systemctl"
    local arg
    for arg in "$@"; do
        cmd_desc+=" ${arg}"
    done

    local op_rc=0
    local op_err=""
    if command -v timeout > /dev/null 2>&1; then
        op_err=$(timeout --signal=TERM --kill-after=10s "${op_timeout}s" systemctl "$@" 2>&1) || op_rc=$?
        if ((op_rc == 124 || op_rc == 137)); then
            debug_file "${cmd_desc} timeout (${op_timeout}s): ${op_err}"
            return "$op_rc"
        fi
    else
        op_err=$(systemctl "$@" 2>&1) || op_rc=$?
    fi

    if [[ -n "$out_err_var" ]]; then
        printf -v "$out_err_var" '%s' "$op_err"
    fi

    if ((op_rc != 0)); then
        debug_file "${cmd_desc} failed: ${op_err}"
        return "$op_rc"
    fi

    return 0
}

# shellcheck disable=SC2120 # Optional out-var is passed by callers from sourced modules.
systemctl_restart_xray_bounded() {
    local out_err_var="${1:-}"
    local restart_timeout="${XRAY_SYSTEMCTL_RESTART_TIMEOUT:-120}"
    if [[ ! "$restart_timeout" =~ ^[0-9]+$ ]] || ((restart_timeout < 10 || restart_timeout > 600)); then
        restart_timeout=120
    fi

    local restart_rc=0
    local restart_err=""
    if command -v timeout > /dev/null 2>&1; then
        restart_err=$(timeout --signal=TERM --kill-after=15s "${restart_timeout}s" systemctl restart xray 2>&1) || restart_rc=$?
        if ((restart_rc == 124 || restart_rc == 137)); then
            if [[ -n "$out_err_var" ]]; then
                printf -v "$out_err_var" '%s' "$restart_err"
            fi
            log ERROR "systemctl restart xray превысил таймаут ${restart_timeout}s"
            debug_file "systemctl restart xray timeout (${restart_timeout}s): ${restart_err}"
            return "$restart_rc"
        fi
    else
        restart_err=$(systemctl restart xray 2>&1) || restart_rc=$?
    fi

    if [[ -n "$out_err_var" ]]; then
        printf -v "$out_err_var" '%s' "$restart_err"
    fi

    if ((restart_rc != 0)); then
        debug_file "systemctl restart xray failed: ${restart_err}"
        return "$restart_rc"
    fi
    return 0
}

running_in_isolated_root_context() {
    local root_sig pid1_root_sig
    root_sig=$(stat -Lc '%d:%i' / 2> /dev/null || true)
    pid1_root_sig=$(stat -Lc '%d:%i' /proc/1/root/. 2> /dev/null || true)
    if [[ -n "$root_sig" && -n "$pid1_root_sig" && "$root_sig" != "$pid1_root_sig" ]]; then
        return 0
    fi
    return 1
}

systemd_running() {
    if [[ "${SYSTEMD_MANAGEMENT_DISABLED:-false}" == "true" ]]; then
        return 1
    fi
    if ! systemctl_available; then
        return 1
    fi
    if running_in_isolated_root_context; then
        return 1
    fi
    [[ -d /run/systemd/system ]] || return 1
    local state
    state=$(systemctl is-system-running 2> /dev/null || true)
    case "$state" in
        running | degraded | starting) return 0 ;;
        *) return 1 ;;
    esac
}

systemd_enable_symlink_path_for_unit() {
    local unit="${1:-}"
    case "$unit" in
        xray.service)
            printf '%s\n' "/etc/systemd/system/multi-user.target.wants/xray.service"
            ;;
        xray-health.timer)
            printf '%s\n' "/etc/systemd/system/timers.target.wants/xray-health.timer"
            ;;
        xray-auto-update.timer)
            printf '%s\n' "/etc/systemd/system/timers.target.wants/xray-auto-update.timer"
            ;;
        *)
            return 1
            ;;
    esac
}
