#!/usr/bin/env bash
# shellcheck shell=bash

: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_GEO_DIR:=}"
: "${XRAY_CONFIG:=/etc/xray/config.json}"
: "${XRAY_ENV:=/etc/xray-reality/config.env}"
: "${XRAY_POLICY:=/etc/xray-reality/policy.json}"
: "${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:=/etc/xray-reality/custom-domains.txt}"
: "${XRAY_KEYS:=/etc/xray/private/keys}"
: "${XRAY_BACKUP:=/var/backups/xray}"
: "${XRAY_LOGS:=/var/log/xray}"
: "${XRAY_HOME:=/var/lib/xray}"
: "${XRAY_DATA_DIR:=/usr/local/share/xray-reality}"
: "${XRAY_SCRIPT_PATH:=/usr/local/bin/xray-reality.sh}"
: "${XRAY_UPDATE_SCRIPT:=/usr/local/bin/xray-reality-update.sh}"
: "${INSTALL_LOG:=/var/log/xray-install.log}"
: "${UPDATE_LOG:=/var/log/xray-update.log}"
: "${DIAG_LOG:=/var/log/xray-diagnose.log}"
: "${HEALTH_LOG:=/var/log/xray/xray-health.log}"
: "${SELF_CHECK_STATE_FILE:=/var/lib/xray/self-check.json}"
: "${SELF_CHECK_HISTORY_FILE:=/var/lib/xray/self-check-history.ndjson}"
: "${MEASUREMENTS_SUMMARY_FILE:=/var/lib/xray/measurements/latest-summary.json}"
: "${MEASUREMENTS_ROTATION_STATE_FILE:=$(dirname "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}")/rotation-state.json}"
: "${MEASUREMENTS_DIR:=/var/lib/xray/measurements}"

managed_path_normalize() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 1
    realpath -m "$path" 2> /dev/null || printf '%s\n' "$path"
}

managed_path_emit_unique() {
    local -A seen=()
    local path normalized
    for path in "$@"; do
        [[ -n "$path" ]] || continue
        normalized=$(managed_path_normalize "$path" || true)
        [[ -n "$normalized" ]] || continue
        if [[ -n "${seen[$normalized]:-}" ]]; then
            continue
        fi
        seen["$normalized"]=1
        printf '%s\n' "$normalized"
    done
}

managed_path_has_project_segment() {
    local normalized
    normalized=$(managed_path_normalize "${1:-}" || true)
    [[ -n "$normalized" ]] || return 1
    [[ "$normalized" =~ (^|/)(xray|xray-reality|network-stealth-core)(/|$) ]]
}

managed_systemd_artifact_paths() {
    managed_path_emit_unique \
        /etc/systemd/system/xray.service \
        /etc/systemd/system/xray-health.service \
        /etc/systemd/system/xray-health.timer \
        /etc/systemd/system/xray-auto-update.service \
        /etc/systemd/system/xray-auto-update.timer \
        /etc/systemd/system/xray-diagnose@.service \
        /etc/systemd/system/multi-user.target.wants/xray.service \
        /etc/systemd/system/timers.target.wants/xray-health.timer \
        /etc/systemd/system/timers.target.wants/xray-auto-update.timer \
        /usr/lib/systemd/system/xray.service \
        /usr/lib/systemd/system/xray-health.service \
        /usr/lib/systemd/system/xray-health.timer \
        /usr/lib/systemd/system/xray-auto-update.service \
        /usr/lib/systemd/system/xray-auto-update.timer \
        /usr/lib/systemd/system/xray-diagnose@.service \
        /lib/systemd/system/xray.service \
        /lib/systemd/system/xray-health.service \
        /lib/systemd/system/xray-health.timer \
        /lib/systemd/system/xray-auto-update.service \
        /lib/systemd/system/xray-auto-update.timer \
        /lib/systemd/system/xray-diagnose@.service
}

managed_binary_script_file_paths() {
    managed_path_emit_unique \
        "$XRAY_BIN" \
        "$XRAY_SCRIPT_PATH" \
        "$XRAY_UPDATE_SCRIPT" \
        /usr/local/bin/xray-health.sh
}

managed_config_state_file_paths() {
    managed_path_emit_unique \
        "$XRAY_CONFIG" \
        "$XRAY_ENV" \
        "$XRAY_POLICY" \
        "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE" \
        "$SELF_CHECK_STATE_FILE" \
        "$SELF_CHECK_HISTORY_FILE" \
        "$MEASUREMENTS_SUMMARY_FILE" \
        "$MEASUREMENTS_ROTATION_STATE_FILE"
}

managed_log_file_paths() {
    managed_path_emit_unique \
        "$INSTALL_LOG" \
        "$UPDATE_LOG" \
        "$DIAG_LOG" \
        "$HEALTH_LOG" \
        /var/log/xray-health.log \
        /var/log/xray.log \
        /var/log/xray-repair.log
}

managed_auxiliary_cleanup_file_paths() {
    managed_path_emit_unique \
        /etc/cron.d/xray-health \
        /etc/logrotate.d/xray \
        /etc/sysctl.d/99-xray.conf \
        /etc/security/limits.d/99-xray.conf
}

managed_runtime_file_paths() {
    managed_binary_script_file_paths
    managed_config_state_file_paths
    managed_log_file_paths
    managed_auxiliary_cleanup_file_paths
}

managed_config_dir_paths() {
    managed_path_emit_unique \
        /etc/xray \
        /etc/xray-reality \
        "$XRAY_KEYS" \
        "$XRAY_DATA_DIR"
}

managed_log_backup_dir_paths() {
    managed_path_emit_unique \
        "$XRAY_LOGS" \
        "$XRAY_BACKUP"
}

managed_state_dir_paths() {
    managed_path_emit_unique \
        "$XRAY_HOME" \
        "$MEASUREMENTS_DIR"
}

managed_runtime_dir_paths() {
    managed_config_dir_paths
    managed_log_backup_dir_paths
    managed_state_dir_paths
}

managed_geo_directories() {
    local -a dirs=()

    if declare -F xray_geo_dir > /dev/null 2>&1; then
        dirs+=("$(xray_geo_dir)")
    elif [[ -n "${XRAY_GEO_DIR:-}" ]]; then
        dirs+=("$XRAY_GEO_DIR")
    fi

    if [[ -n "${XRAY_BIN:-}" ]]; then
        dirs+=("$(dirname "$XRAY_BIN")")
    fi
    dirs+=("/usr/local/share/xray")

    managed_path_emit_unique "${dirs[@]}"
}

managed_geo_file_paths() {
    local geo_dir
    while IFS= read -r geo_dir; do
        [[ -n "$geo_dir" ]] || continue
        managed_path_emit_unique \
            "${geo_dir}/geoip.dat" \
            "${geo_dir}/geosite.dat"
    done < <(managed_geo_directories)
}

managed_runtime_artifact_paths() {
    managed_systemd_artifact_paths
    managed_runtime_file_paths
    managed_runtime_dir_paths
    managed_geo_file_paths
}

managed_runtime_artifacts_present() {
    local candidate
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            return 0
        fi
    done < <(managed_runtime_artifact_paths)
    return 1
}

managed_source_tree_root_files() {
    printf '%s\n' \
        domains.tiers \
        sni_pools.map \
        transport_endpoints.map \
        lib.sh \
        install.sh \
        config.sh \
        service.sh \
        health.sh \
        export.sh
}
