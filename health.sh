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
if [[ ! -f "$SELF_CHECK_MODULE" ]]; then
    echo "ERROR: не найден модуль self-check: $SELF_CHECK_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/health/self_check.sh
source "$SELF_CHECK_MODULE"

MEASUREMENTS_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/health/measurements.sh"
if [[ ! -f "$MEASUREMENTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    MEASUREMENTS_MODULE="$XRAY_DATA_DIR/modules/health/measurements.sh"
fi
if [[ ! -f "$MEASUREMENTS_MODULE" ]]; then
    echo "ERROR: не найден модуль measurements: $MEASUREMENTS_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/health/measurements.sh
source "$MEASUREMENTS_MODULE"

health_monitoring_collect_port_lines() {
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_v4_ref="$1"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_v6_ref="$2"
    local calc_ports_v4_line calc_ports_v6_line
    calc_ports_v4_line=$(printf "%s " "${PORTS[@]}")
    calc_ports_v6_line=""

    local -a safe_ports_v6=()
    if [[ "${HAS_IPV6:-false}" == true ]] && declare -p PORTS_V6 > /dev/null 2>&1; then
        safe_ports_v6=("${PORTS_V6[@]}")
    fi
    if ((${#safe_ports_v6[@]} > 0)); then
        calc_ports_v6_line=$(printf "%s " "${safe_ports_v6[@]}")
    fi

    # shellcheck disable=SC2034 # nameref target is used by caller.
    out_v4_ref="$calc_ports_v4_line"
    # shellcheck disable=SC2034 # nameref target is used by caller.
    out_v6_ref="$calc_ports_v6_line"
}

health_monitoring_normalize_settings() {
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_retention_ref="$1"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_size_bytes_ref="$2"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_interval_ref="$3"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_domain_health_ref="$4"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_ports_ref="$5"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_probe_timeout_ref="$6"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_rate_limit_ref="$7"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_max_probes_ref="$8"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_health_log_ref="$9"
    # shellcheck disable=SC2034 # nameref writes caller variables.
    local -n out_xray_config_ref="${10}"

    local calc_log_retention="${LOG_RETENTION_DAYS:-30}"
    local calc_log_max_size_mb="${LOG_MAX_SIZE_MB:-10}"
    local calc_log_max_size_bytes=0
    local calc_health_interval="${HEALTH_CHECK_INTERVAL:-120}"
    local calc_domain_health_file calc_reality_test_ports calc_probe_timeout calc_rate_limit_ms calc_max_probes
    local calc_logs_dir calc_health_log calc_xray_config

    if [[ ! "$calc_log_retention" =~ ^[0-9]+$ ]] || ((calc_log_retention < 1 || calc_log_retention > 3650)); then
        log WARN "Некорректный LOG_RETENTION_DAYS: ${calc_log_retention} (используем 30)"
        calc_log_retention=30
    fi
    if [[ ! "$calc_log_max_size_mb" =~ ^[0-9]+$ ]] || ((calc_log_max_size_mb < 1 || calc_log_max_size_mb > 1024)); then
        log WARN "Некорректный LOG_MAX_SIZE_MB: ${calc_log_max_size_mb} (используем 10)"
        calc_log_max_size_mb=10
    fi
    calc_log_max_size_bytes=$((calc_log_max_size_mb * 1048576))
    if [[ ! "$calc_health_interval" =~ ^[0-9]+$ ]] || ((calc_health_interval < 10 || calc_health_interval > 86400)); then
        log WARN "Некорректный HEALTH_CHECK_INTERVAL: ${calc_health_interval} (используем 120)"
        calc_health_interval=120
    fi

    calc_domain_health_file="${DOMAIN_HEALTH_FILE//$'\n'/}"
    calc_domain_health_file="${calc_domain_health_file//$'\r'/}"
    if [[ -z "$calc_domain_health_file" ]]; then
        calc_domain_health_file="/var/lib/xray/domain-health.json"
    fi

    calc_logs_dir="${XRAY_LOGS:-/var/log/xray}"
    calc_logs_dir=$(printf '%s' "$calc_logs_dir" | tr -d '\000-\037\177')
    if [[ -z "$calc_logs_dir" || "$calc_logs_dir" != /* ]]; then
        calc_logs_dir="/var/log/xray"
    fi

    calc_health_log="${HEALTH_LOG:-${calc_logs_dir%/}/xray-health.log}"
    calc_health_log=$(printf '%s' "$calc_health_log" | tr -d '\000-\037\177')
    if [[ -z "$calc_health_log" || "$calc_health_log" != /* ]]; then
        calc_health_log="${calc_logs_dir%/}/xray-health.log"
    fi

    calc_xray_config="${XRAY_CONFIG:-/etc/xray/config.json}"
    calc_xray_config=$(printf '%s' "$calc_xray_config" | tr -d '\000-\037\177')
    if [[ -z "$calc_xray_config" || "$calc_xray_config" != /* ]]; then
        calc_xray_config="/etc/xray/config.json"
    fi

    calc_reality_test_ports="${REALITY_TEST_PORTS//[^0-9, ]/}"
    if [[ -z "$calc_reality_test_ports" ]]; then
        calc_reality_test_ports="443,8443"
    fi

    calc_probe_timeout="$DOMAIN_HEALTH_PROBE_TIMEOUT"
    if [[ ! "$calc_probe_timeout" =~ ^[0-9]+$ ]] || ((calc_probe_timeout < 1 || calc_probe_timeout > 15)); then
        calc_probe_timeout=2
    fi

    calc_rate_limit_ms="$DOMAIN_HEALTH_RATE_LIMIT_MS"
    if [[ ! "$calc_rate_limit_ms" =~ ^[0-9]+$ ]] || ((calc_rate_limit_ms < 0 || calc_rate_limit_ms > 10000)); then
        calc_rate_limit_ms=250
    fi

    calc_max_probes="$DOMAIN_HEALTH_MAX_PROBES"
    if [[ ! "$calc_max_probes" =~ ^[0-9]+$ ]] || ((calc_max_probes < 1 || calc_max_probes > 200)); then
        calc_max_probes=20
    fi

    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_retention_ref="$calc_log_retention"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_size_bytes_ref="$calc_log_max_size_bytes"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_interval_ref="$calc_health_interval"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_domain_health_ref="$calc_domain_health_file"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_ports_ref="$calc_reality_test_ports"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_probe_timeout_ref="$calc_probe_timeout"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_rate_limit_ref="$calc_rate_limit_ms"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_max_probes_ref="$calc_max_probes"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_health_log_ref="$calc_health_log"
    # shellcheck disable=SC2034 # nameref targets are used by caller.
    out_xray_config_ref="$calc_xray_config"
}

health_monitoring_emit_health_script_prelude() {
    cat << 'HEALTH_EOF_PRELUDE'

check_xray_health() {
    local state
    state=$(systemctl is-active xray 2>/dev/null || true)
    [[ "$state" == "active" ]] || return 1

    local port
    for port in "${PORTS_V4[@]}"; do
        [[ -z "$port" ]] && continue
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q . || return 1
    done

    for port in "${PORTS_V6[@]}"; do
        [[ -z "$port" ]] && continue
        ss -H -ltn6 "sport = :${port}" 2>/dev/null | grep -q . || {
            echo "[$(date)] WARN: IPv6 port ${port} not listening" >> "$LOG"
            return 1
        }
    done

    pgrep -x xray >/dev/null || return 1

    return 0
}

write_count() {
    local file="$1"
    local val="$2"
    local lockfile="${file}.lock"
    local tmp

    (
        flock -x -w 5 200 || { echo "[$(date)] WARN: flock write failed for $file" >> "$LOG"; exit 1; }
        tmp=$(mktemp "${file}.XXXXXX")
        trap 'rm -f "$tmp" 2>/dev/null || true' EXIT INT TERM
        chmod 600 "$tmp"
        printf '%s' "$val" > "$tmp"
        mv "$tmp" "$file"
        trap - EXIT INT TERM
        chmod 600 "$file"
    ) 200>"$lockfile"
}

read_count() {
    local file="$1"
    local lockfile="${file}.lock"
    local val
    (
        flock -s -w 5 200 || { echo "[$(date)] WARN: flock read failed for $file" >> "$LOG"; echo 0; exit 1; }
        val=$(cat "$file" 2>/dev/null || echo 0)
        printf '%s' "$val"
    ) 200>"$lockfile"
}

ms_to_sleep() {
    local ms="$1"
    if [[ ! "$ms" =~ ^[0-9]+$ ]] || ((ms <= 0)); then
        printf '0'
        return 0
    fi
    awk -v v="$ms" 'BEGIN { printf "%.3f", v / 1000 }'
}

probe_domain() {
    local domain="$1"
    local timeout_sec="$2"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

    if [[ ! "$timeout_sec" =~ ^[0-9]+$ ]] || ((timeout_sec < 1 || timeout_sec > 15)); then
        timeout_sec=2
    fi

    local -a ports=()
    mapfile -t ports < <(tr ',[:space:]' '\n' <<< "$REALITY_TEST_PORTS" | awk 'NF')
    if [[ ${#ports[@]} -eq 0 ]]; then
        ports=(443 8443)
    fi

    if command -v timeout > /dev/null 2>&1 && command -v openssl > /dev/null 2>&1; then
        local port
        for port in "${ports[@]}"; do
            [[ "$port" =~ ^[0-9]+$ ]] || continue
            # shellcheck disable=SC2016 # Single quotes intentional - args passed via $1/$2
            if timeout "$timeout_sec" bash -c 'echo | openssl s_client -connect "$1:$2" -servername "$1" 2>/dev/null' _ "$domain" "$port" | grep -q "CONNECTED"; then
                return 0
            fi
        done
        return 1
    fi

    if command -v curl > /dev/null 2>&1; then
        if curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
            -I --connect-timeout "$timeout_sec" --max-time "$timeout_sec" "https://${domain}" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

collect_reality_domains() {
    local cfg="${XRAY_CONFIG_PATH:-/etc/xray/config.json}"
    [[ -f "$cfg" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0

    jq -r '.inbounds[]? | .streamSettings.realitySettings.dest // empty' "$cfg" 2> /dev/null |
        sed 's/:.*//' |
        awk 'NF && !seen[$0]++'
}
HEALTH_EOF_PRELUDE
}

health_monitoring_emit_health_script_domain_health() {
    cat << 'HEALTH_EOF_DOMAIN_HEALTH'
update_domain_health() {
    command -v jq > /dev/null 2>&1 || return 0

    local -a domains=()
    mapfile -t domains < <(collect_reality_domains)
    if [[ ${#domains[@]} -eq 0 ]]; then
        return 0
    fi

    local file="$DOMAIN_HEALTH_FILE"
    if [[ -z "$file" ]]; then
        file="/var/lib/xray/domain-health.json"
    fi
    local health_dir
    health_dir=$(dirname "$file")
    install -d -m 700 "$health_dir" 2>/dev/null || true

    local lockfile="${file}.lock"
    (
        flock -x -w 5 200 || { echo "[$(date)] WARN: flock update failed for ${file}" >> "$LOG"; exit 0; }

        local state='{"domains":{},"updated_at":""}'
        if [[ -f "$file" ]] && jq empty "$file" > /dev/null 2>&1; then
            state=$(cat "$file")
        fi

        local base_timeout="$DOMAIN_HEALTH_PROBE_TIMEOUT"
        if [[ ! "$base_timeout" =~ ^[0-9]+$ ]] || ((base_timeout < 1 || base_timeout > 15)); then
            base_timeout=2
        fi
        local rate_limit_ms="$DOMAIN_HEALTH_RATE_LIMIT_MS"
        if [[ ! "$rate_limit_ms" =~ ^[0-9]+$ ]] || ((rate_limit_ms < 0 || rate_limit_ms > 10000)); then
            rate_limit_ms=250
        fi
        local max_probes="$DOMAIN_HEALTH_MAX_PROBES"
        if [[ ! "$max_probes" =~ ^[0-9]+$ ]] || ((max_probes < 1 || max_probes > 200)); then
            max_probes=20
        fi

        local now
        now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
        local probe_count=0
        local domain
        for domain in "${domains[@]}"; do
            if ((probe_count >= max_probes)); then
                echo "[$(date)] INFO: domain probe cap reached (${max_probes}), remaining domains skipped" >> "$LOG"
                break
            fi

            local fail_streak score timeout_sec
            fail_streak=$(echo "$state" | jq -r --arg d "$domain" '.domains[$d].fail_streak // 0' 2> /dev/null || echo 0)
            score=$(echo "$state" | jq -r --arg d "$domain" '.domains[$d].score // 0' 2> /dev/null || echo 0)
            [[ "$fail_streak" =~ ^[0-9]+$ ]] || fail_streak=0
            [[ "$score" =~ ^-?[0-9]+$ ]] || score=0

            timeout_sec=$base_timeout
            if ((fail_streak >= 6)); then
                timeout_sec=$((timeout_sec + 4))
            elif ((fail_streak >= 3)); then
                timeout_sec=$((timeout_sec + 2))
            fi
            if ((score >= 20 && timeout_sec > 1)); then
                timeout_sec=$((timeout_sec - 1))
            fi
            ((timeout_sec > 15)) && timeout_sec=15
            ((timeout_sec < 1)) && timeout_sec=1

            if probe_domain "$domain" "$timeout_sec"; then
                state=$(echo "$state" | jq --arg d "$domain" --arg now "$now" '
                    .domains[$d] = ((.domains[$d] // {score:0, success:0, fail:0, fail_streak:0})
                        | .success = ((.success // 0) + 1)
                        | .score = (((.score // 0) + 3) | if . > 100 then 100 else . end)
                        | .fail_streak = 0
                        | .last_ok = $now
                    )')
            else
                state=$(echo "$state" | jq --arg d "$domain" --arg now "$now" '
                    .domains[$d] = ((.domains[$d] // {score:0, success:0, fail:0, fail_streak:0})
                        | .fail = ((.fail // 0) + 1)
                        | .fail_streak = ((.fail_streak // 0) + 1)
                        | .score = (((.score // 0) - 5) | if . < -100 then -100 else . end)
                        | .last_fail = $now
                    )')
            fi
            probe_count=$((probe_count + 1))

            if ((rate_limit_ms > 0)) && ((probe_count < max_probes)); then
                local jitter_ms total_ms sleep_s
                jitter_ms=$((RANDOM % 121))
                total_ms=$((rate_limit_ms + jitter_ms))
                sleep_s=$(ms_to_sleep "$total_ms")
                if [[ "$sleep_s" != "0" ]]; then
                    sleep "$sleep_s"
                fi
            fi
        done

        state=$(echo "$state" | jq --arg now "$now" '.updated_at = $now')
        local tmp
        tmp=$(mktemp "${file}.XXXXXX")
        trap 'rm -f "$tmp" 2>/dev/null || true' EXIT INT TERM
        chmod 600 "$tmp"
        printf '%s\n' "$state" | jq '.' > "$tmp"
        mv "$tmp" "$file"
        chmod 600 "$file"
        trap - EXIT INT TERM
    ) 200>"$lockfile"
}
HEALTH_EOF_DOMAIN_HEALTH
}

health_monitoring_emit_health_script_runtime_and_rotation() {
    cat << 'HEALTH_EOF_RUNTIME'
restart_xray_bounded() {
    local timeout_s="${HEALTH_SYSTEMCTL_RESTART_TIMEOUT:-60}"
    if [[ ! "$timeout_s" =~ ^[0-9]+$ ]] || ((timeout_s < 10 || timeout_s > 600)); then
        timeout_s=60
    fi
    if command -v timeout > /dev/null 2>&1; then
        timeout --signal=TERM --kill-after=10s "${timeout_s}s" systemctl restart xray
    else
        systemctl restart xray
    fi
}

FAIL_COUNT=$(read_count "$FAIL_COUNT_FILE")

if ! check_xray_health; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    write_count "$FAIL_COUNT_FILE" "$FAIL_COUNT"
    echo "[$(date)] Xray health check failed ($FAIL_COUNT/$MAX_FAILS)" >> "$LOG"

    if [[ $FAIL_COUNT -ge $MAX_FAILS ]]; then
        echo "[$(date)] Max Xray failures reached - restarting" >> "$LOG"
        if restart_xray_bounded; then
            write_count "$FAIL_COUNT_FILE" "0"
            sleep 3
        else
            echo "[$(date)] WARN: xray restart failed or timed out" >> "$LOG"
        fi
    fi
else
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo "[$(date)] Xray recovered after $FAIL_COUNT failure(s)" >> "$LOG"
    fi
    write_count "$FAIL_COUNT_FILE" "0"
fi

update_domain_health || echo "[$(date)] WARN: domain health update failed" >> "$LOG"

log_file_size() {
    local file="$1"
    if command -v stat > /dev/null 2>&1; then
        stat -c%s "$file" 2> /dev/null && return 0
        stat -f%z "$file" 2> /dev/null && return 0
    fi
    wc -c < "$file" 2> /dev/null || echo 0
}

find "$LOG_DIR" -maxdepth 1 -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
if [[ -f "$LOG" ]] && [[ $(log_file_size "$LOG") -gt $LOG_MAX_SIZE_BYTES ]]; then
    truncate -s 0 "$LOG" 2>/dev/null || true
fi
HEALTH_EOF_RUNTIME
}

health_monitoring_emit_health_script_body() {
    health_monitoring_emit_health_script_prelude
    health_monitoring_emit_health_script_domain_health
    health_monitoring_emit_health_script_runtime_and_rotation
}

health_monitoring_write_health_script() {
    local ports_v4_line="$1"
    local ports_v6_line="$2"
    local log_retention="$3"
    local log_max_size_bytes="$4"
    local safe_domain_health_file="$5"
    local safe_reality_test_ports="$6"
    local safe_probe_timeout="$7"
    local safe_rate_limit_ms="$8"
    local safe_max_probes="$9"
    local safe_health_log="${10}"
    local safe_xray_config="${11}"

    backup_file /usr/local/bin/xray-health.sh
    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        printf 'LOG=%q\n' "$safe_health_log"
        printf 'LOG_DIR=%q\n' "$(dirname "$safe_health_log")"
        echo 'STATE_DIR="/var/lib/xray/health"'
        echo "FAIL_COUNT_FILE=\"\$STATE_DIR/fail-count\""
        printf 'XRAY_CONFIG_PATH=%q\n' "$safe_xray_config"
        printf 'DOMAIN_HEALTH_FILE=%q\n' "$safe_domain_health_file"
        printf 'REALITY_TEST_PORTS=%q\n' "$safe_reality_test_ports"
        printf 'DOMAIN_HEALTH_PROBE_TIMEOUT=%q\n' "$safe_probe_timeout"
        printf 'DOMAIN_HEALTH_RATE_LIMIT_MS=%q\n' "$safe_rate_limit_ms"
        printf 'DOMAIN_HEALTH_MAX_PROBES=%q\n' "$safe_max_probes"
        # shellcheck disable=SC2016 # Single quotes intentional - generating script
        echo 'MAX_FAILS="${MAX_HEALTH_FAILURES:-3}"'
        echo "LOG_RETENTION_DAYS=${log_retention}"
        echo "LOG_MAX_SIZE_BYTES=${log_max_size_bytes}"
        echo 'umask 077'
        echo "install -d -m 700 \"\$STATE_DIR\" 2>/dev/null || true"
        echo "install -d -m 750 \"\$LOG_DIR\" 2>/dev/null || true"
        printf 'PORTS_V4=(%s)\n' "$ports_v4_line"
        printf 'PORTS_V6=(%s)\n' "$ports_v6_line"
        health_monitoring_emit_health_script_body
    } | atomic_write /usr/local/bin/xray-health.sh 0755
}

health_monitoring_install_systemd_units() {
    local safe_health_interval="$1"
    backup_file /etc/systemd/system/xray-health.service
    atomic_write /etc/systemd/system/xray-health.service 0644 << 'EOF'
[Unit]
Description=Xray Health Check
After=network.target

[Service]
Type=oneshot
TimeoutStartSec=30min
ExecStart=/usr/local/bin/xray-health.sh
EOF

    backup_file /etc/systemd/system/xray-health.timer
    atomic_write /etc/systemd/system/xray-health.timer 0644 << EOF
[Unit]
Description=Xray Health Check Time

[Timer]
OnBootSec=2min
OnUnitActiveSec=${safe_health_interval}s
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

setup_health_monitoring() {
    log STEP "Настраиваем расширенный мониторинг..."

    if ! systemctl_available; then
        log WARN "systemctl не найден; мониторинг пропущен"
        return 0
    fi
    if ! systemd_running; then
        log WARN "systemd не запущен; мониторинг пропущен"
        return 0
    fi

    local ports_v4_line ports_v6_line
    health_monitoring_collect_port_lines ports_v4_line ports_v6_line

    local log_retention log_max_size_bytes safe_health_interval
    local safe_domain_health_file safe_reality_test_ports safe_probe_timeout safe_rate_limit_ms safe_max_probes
    local safe_health_log safe_xray_config
    health_monitoring_normalize_settings \
        log_retention \
        log_max_size_bytes \
        safe_health_interval \
        safe_domain_health_file \
        safe_reality_test_ports \
        safe_probe_timeout \
        safe_rate_limit_ms \
        safe_max_probes \
        safe_health_log \
        safe_xray_config

    health_monitoring_write_health_script \
        "$ports_v4_line" \
        "$ports_v6_line" \
        "$log_retention" \
        "$log_max_size_bytes" \
        "$safe_domain_health_file" \
        "$safe_reality_test_ports" \
        "$safe_probe_timeout" \
        "$safe_rate_limit_ms" \
        "$safe_max_probes" \
        "$safe_health_log" \
        "$safe_xray_config"
    health_monitoring_install_systemd_units "$safe_health_interval"

    if [[ -f /etc/cron.d/xray-health ]]; then
        backup_file /etc/cron.d/xray-health
        rm -f /etc/cron.d/xray-health
    fi

    if ! systemctl_run_bounded daemon-reload; then
        log WARN "systemd недоступен; мониторинг пропущен"
        return 0
    fi
    local health_timer_enable_link=""
    local health_timer_enable_link_missing=false
    if health_timer_enable_link=$(systemd_enable_symlink_path_for_unit xray-health.timer 2> /dev/null); then
        if [[ ! -e "$health_timer_enable_link" && ! -L "$health_timer_enable_link" ]]; then
            health_timer_enable_link_missing=true
        fi
    fi
    if systemctl_run_bounded enable --now xray-health.timer; then
        if [[ "$health_timer_enable_link_missing" == true && -n "$health_timer_enable_link" ]] && declare -F record_created_path_literal > /dev/null 2>&1; then
            if [[ -e "$health_timer_enable_link" || -L "$health_timer_enable_link" ]]; then
                record_created_path_literal "$health_timer_enable_link"
            fi
        fi
        log OK "Мониторинг настроен (systemd timer каждые ${safe_health_interval}s)"
    else
        log WARN "Не удалось включить systemd-таймер мониторинга"
    fi
}

diagnose() {
    log STEP "Собираем диагностику..."
    set +e

    if {
        echo "===== CONTEXT ====="
        echo "Date: $(date)"
        echo "Failed unit: ${FAILED_UNIT:-N/A}"
        echo "Script: ${SCRIPT_NAME} v${SCRIPT_VERSION}"
        echo "Kernel: $(uname -a)"
        [[ -f /etc/os-release ]] && cat /etc/os-release
        echo ""

        echo "===== SOURCE ====="
        echo "Kind: ${XRAY_SOURCE_KIND:-unknown}"
        echo "Ref: ${XRAY_SOURCE_REF:-unknown}"
        echo "Commit: ${XRAY_SOURCE_COMMIT:-unknown}"
        echo ""

        echo "===== XRAY ====="
        if [[ -x "$XRAY_BIN" ]]; then
            "$XRAY_BIN" version | head -2
        fi
        [[ -f "$XRAY_CONFIG" ]] && ls -l "$XRAY_CONFIG"
        if [[ -x "$XRAY_BIN" && -f "$XRAY_CONFIG" ]]; then
            xray_config_test 2>&1 | tail -n 5 || true
        fi
        if [[ -f "${SELF_CHECK_STATE_FILE:-/var/lib/xray/self-check.json}" ]]; then
            echo ""
            echo "===== SELF-CHECK ====="
            jq '.' "${SELF_CHECK_STATE_FILE:-/var/lib/xray/self-check.json}" 2> /dev/null || cat "${SELF_CHECK_STATE_FILE:-/var/lib/xray/self-check.json}" 2> /dev/null || true
        fi
        if [[ -f "${SELF_CHECK_HISTORY_FILE:-/var/lib/xray/self-check-history.ndjson}" ]]; then
            echo ""
            echo "===== SELF-CHECK HISTORY (tail 10) ====="
            tail -n 10 "${SELF_CHECK_HISTORY_FILE:-/var/lib/xray/self-check-history.ndjson}" 2> /dev/null || true
        fi
        if [[ -f "${XRAY_POLICY:-/etc/xray-reality/policy.json}" ]]; then
            echo ""
            echo "===== POLICY ====="
            jq '.' "${XRAY_POLICY:-/etc/xray-reality/policy.json}" 2> /dev/null || cat "${XRAY_POLICY:-/etc/xray-reality/policy.json}" 2> /dev/null || true
        fi
        if [[ -f "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}" ]]; then
            echo ""
            echo "===== FIELD MEASUREMENTS ====="
            jq '.' "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}" 2> /dev/null || cat "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}" 2> /dev/null || true
        fi
        echo ""

        echo "===== SYSTEMD ====="
        systemctl status xray --no-pager || true
        systemctl list-units --type=service --state=failed --no-pager || true
        echo ""

        echo "===== JOURNAL ====="
        journalctl -u xray -n 200 --no-pager || true
        echo ""

        echo "===== NETWORK ====="
        ss -ltnp 2> /dev/null || true
        echo ""

        echo "===== RESOURCES ====="
        df -h 2> /dev/null || true
        free -m 2> /dev/null || true
        echo ""
    } > "$DIAG_LOG" 2>&1; then
        set -e
        log OK "Диагностика сохранена в $DIAG_LOG"
    else
        set -e
        log WARN "Не удалось сохранить диагностику в $DIAG_LOG"
    fi
}

test_reality_connectivity() {
    log STEP "Проверяем работоспособность Reality..."

    sleep 2

    if ! systemctl_available; then
        log WARN "systemctl не найден; проверка Reality пропущена"
        return 0
    fi
    if ! systemd_running; then
        log WARN "systemd не запущен; проверка Reality пропущена"
        return 0
    fi

    if ! systemctl is-active --quiet xray; then
        log ERROR "Xray не активен"
        log ERROR "Проверьте логи: journalctl -u xray -n 50"
        return 1
    fi
    if ! pgrep -x xray > /dev/null; then
        log ERROR "Процесс Xray не найден"
        return 1
    fi

    if ! xray_config_test_ok "$XRAY_CONFIG"; then
        log ERROR "Xray отклонил конфигурацию"
        return 1
    fi

    local test_passed=0
    local test_total=$NUM_CONFIGS

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local port="${PORTS[$i]}"
        if port_is_listening "$port"; then
            log OK "Config $((i + 1)) (порт ${port}): порт слушается"
            test_passed=$((test_passed + 1))
        else
            log WARN "Config $((i + 1)) (порт ${port}): порт не слушается"
        fi

        if [[ "$HAS_IPV6" == true ]] && [[ -n "${PORTS_V6[$i]:-}" ]]; then
            local port_v6="${PORTS_V6[$i]}"
            if port_is_listening "$port_v6"; then
                log INFO "Config $((i + 1)) (IPv6 порт ${port_v6}): слушается"
            else
                log WARN "Config $((i + 1)) (IPv6 порт ${port_v6}): не слушается"
            fi
        fi
    done

    if [[ $test_passed -eq 0 ]]; then
        log ERROR "Ни один порт не слушается!"
        log ERROR "Проверьте логи: journalctl -u xray -n 50"
        return 1
    elif [[ $test_passed -lt $test_total ]]; then
        log WARN "Слушается: ${test_passed}/${test_total} портов"
        log INFO "Частичная работоспособность - продолжаем установку"
    else
        log OK "Все порты (${test_passed}/${test_total}) слушаются"
    fi
}

post_action_verdict() {
    self_check_post_action_verdict "${1:-action}"
}
