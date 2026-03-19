#!/usr/bin/env bats

@test "setup_health_monitoring handles unset PORTS_V6 when HAS_IPV6=true" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443 444)
    HAS_IPV6=true
    unset -v PORTS_V6
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    DOMAIN_HEALTH_FILE=""
    REALITY_TEST_PORTS="443,8443"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20

    setup_health_monitoring
    grep -q "^PORTS_V6=()$" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring applies safe fallback values for invalid inputs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    LOG_RETENTION_DAYS="broken"
    LOG_MAX_SIZE_MB="0"
    HEALTH_CHECK_INTERVAL="100000"
    DOMAIN_HEALTH_FILE=""
    REALITY_TEST_PORTS="@@@"
    DOMAIN_HEALTH_PROBE_TIMEOUT=99
    DOMAIN_HEALTH_RATE_LIMIT_MS=-1
    DOMAIN_HEALTH_MAX_PROBES=999

    setup_health_monitoring
    grep -q "^set -euo pipefail$" "$HEALTH_SCRIPT_OUT"
    grep -q "^LOG_RETENTION_DAYS=30$" "$HEALTH_SCRIPT_OUT"
    grep -q "^LOG_MAX_SIZE_BYTES=10485760$" "$HEALTH_SCRIPT_OUT"
    grep -q "^DOMAIN_HEALTH_PROBE_TIMEOUT=2$" "$HEALTH_SCRIPT_OUT"
    grep -q "^DOMAIN_HEALTH_RATE_LIMIT_MS=250$" "$HEALTH_SCRIPT_OUT"
    grep -q "^DOMAIN_HEALTH_MAX_PROBES=20$" "$HEALTH_SCRIPT_OUT"
    grep -q "^TimeoutStartSec=90s$" "$HEALTH_SERVICE_OUT"
    ! grep -q "split_list" "$HEALTH_SCRIPT_OUT"
    grep -q "^OnUnitActiveSec=120s$" "$HEALTH_TIMER_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring uses configured health log paths" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    REALITY_TEST_PORTS="443,8443"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20
    XRAY_LOGS="/opt/xray/log"
    HEALTH_LOG="/opt/xray/log/custom-health.log"

    setup_health_monitoring
    grep -q "^LOG=/opt/xray/log/custom-health.log$" "$HEALTH_SCRIPT_OUT"
    grep -q "^LOG_DIR=/opt/xray/log$" "$HEALTH_SCRIPT_OUT"
    grep -Fq "find \"\$LOG_DIR\" -maxdepth 1 -name \"*.log\"" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring uses nested xray health log path by default" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./modules/service/uninstall.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    XRAY_LOGS="/var/log/xray"
    HEALTH_LOG=""
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    REALITY_TEST_PORTS="443,8443"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20

    setup_health_monitoring
    grep -q "^LOG=/var/log/xray/xray-health.log$" "$HEALTH_SCRIPT_OUT"
    grep -q "^LOG_DIR=/var/log/xray$" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring uses safe fail-count increment under set -e" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    REALITY_TEST_PORTS="443,8443"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20

    setup_health_monitoring
    grep -Fq "FAIL_COUNT=\$(read_count \"\$FAIL_COUNT_FILE\") || {" "$HEALTH_SCRIPT_OUT"
    grep -Fq "FAIL_COUNT=\$((FAIL_COUNT + 1))" "$HEALTH_SCRIPT_OUT"
    grep -Fq "write_count \"\$FAIL_COUNT_FILE\" \"\$FAIL_COUNT\" \\" "$HEALTH_SCRIPT_OUT"
    grep -Fq "WARN: could not persist fail count" "$HEALTH_SCRIPT_OUT"
    grep -Fq "WARN: could not reset fail count" "$HEALTH_SCRIPT_OUT"
    ! grep -q "\\(\\(FAIL_COUNT\\+\\+\\)\\)" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring embeds runtime xray config path into health script" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    REALITY_TEST_PORTS="443,8443"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20
    XRAY_CONFIG="/opt/xray/etc/custom-config.json"

    setup_health_monitoring
    grep -q "^XRAY_CONFIG_PATH=/opt/xray/etc/custom-config.json$" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring emits curl-first domain probe contract" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"
    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl_run_bounded() { return 1; }
    systemd_enable_symlink_path_for_unit() { return 1; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    REALITY_TEST_PORTS="443"
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    setup_health_monitoring

    grep -q "^probe_domain_with_curl()" "$HEALTH_SCRIPT_OUT"
    grep -q "url=\"https://\\\${domain}:\\\${port}\"" "$HEALTH_SCRIPT_OUT"
    grep -q "probe_domain_with_curl \"\\\$domain\" \"\\\$port\" \"\\\$timeout_sec\"" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring emits verified openssl fallback instead of CONNECTED grep" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"
    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl_run_bounded() { return 1; }
    systemd_enable_symlink_path_for_unit() { return 1; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    REALITY_TEST_PORTS="443"
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    setup_health_monitoring

    grep -q "^probe_domain_with_openssl()" "$HEALTH_SCRIPT_OUT"
    grep -q "Verify return code: 0 (ok)" "$HEALTH_SCRIPT_OUT"
    grep -q -- "-verify_return_error -verify_hostname" "$HEALTH_SCRIPT_OUT"
    ! grep -q "grep -q \"CONNECTED\"" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "setup_health_monitoring uses printf-safe jq state updates in generated domain health script" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    HEALTH_SCRIPT_OUT="$tmp_dir/xray-health.sh"
    HEALTH_SERVICE_OUT="$tmp_dir/xray-health.service"
    HEALTH_TIMER_OUT="$tmp_dir/xray-health.timer"

    log() { :; }
    backup_file() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl_run_bounded() { return 1; }
    systemd_enable_symlink_path_for_unit() { return 1; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      local out="$target"
      case "$target" in
        /usr/local/bin/xray-health.sh) out="$HEALTH_SCRIPT_OUT" ;;
        /etc/systemd/system/xray-health.service) out="$HEALTH_SERVICE_OUT" ;;
        /etc/systemd/system/xray-health.timer) out="$HEALTH_TIMER_OUT" ;;
      esac
      cat > "$out"
      [[ -n "$mode" ]] && chmod "$mode" "$out"
    }

    PORTS=(443)
    HAS_IPV6=false
    REALITY_TEST_PORTS="443"
    DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    DOMAIN_HEALTH_PROBE_TIMEOUT=2
    DOMAIN_HEALTH_RATE_LIMIT_MS=250
    DOMAIN_HEALTH_MAX_PROBES=20
    LOG_RETENTION_DAYS=30
    LOG_MAX_SIZE_MB=10
    HEALTH_CHECK_INTERVAL=120
    setup_health_monitoring

    grep -Fq "fail_streak=\$(printf '\''%s\\n'\'' \"\$state\" | jq -r" "$HEALTH_SCRIPT_OUT"
    grep -Fq "score=\$(printf '\''%s\\n'\'' \"\$state\" | jq -r" "$HEALTH_SCRIPT_OUT"
    grep -Fq "state=\$(printf '\''%s\\n'\'' \"\$state\" | jq --arg d \"\$domain\" --arg now \"\$now\"" "$HEALTH_SCRIPT_OUT"
    grep -Fq "state=\$(printf '\''%s\\n'\'' \"\$state\" | jq --arg now \"\$now\" '\''.updated_at = \$now'\'')" "$HEALTH_SCRIPT_OUT"
    ! grep -Fq "echo \"\$state\" | jq" "$HEALTH_SCRIPT_OUT"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "test_reality_connectivity avoids fixed sleep when xray is already ready" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    sleep_calls=0
    NUM_CONFIGS=1
    PORTS=(24443)
    HAS_IPV6=false

    log() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() {
      [[ "$1" == "is-active" ]] && return 0
      return 0
    }
    pgrep() { return 0; }
    xray_config_test_ok() { return 0; }
    port_is_listening() { return 0; }
    sleep() { sleep_calls=$((sleep_calls + 1)); }

    test_reality_connectivity
    [[ "$sleep_calls" -eq 0 ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "diagnose writes collected output to DIAG_LOG" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_log=$(mktemp)
    trap "rm -f \"$tmp_log\"" EXIT

    DIAG_LOG="$tmp_log"
    XRAY_BIN="/nonexistent/xray"
    XRAY_CONFIG="/nonexistent/config.json"

    log() { :; }
    systemctl() { return 0; }
    journalctl() { return 0; }
    ss() { return 0; }
    df() { return 0; }
    free() { return 0; }

    diagnose
    test -s "$DIAG_LOG"
    grep -q "===== CONTEXT =====" "$DIAG_LOG"
    grep -q "===== XRAY =====" "$DIAG_LOG"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self_check_status_summary_tsv reads persisted state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    SELF_CHECK_STATE_FILE="$tmp_dir/self-check.json"
    cat > "$SELF_CHECK_STATE_FILE" <<EOF
{
  "verdict": "warning",
  "action": "repair",
  "checked_at": "2026-03-07T12:00:00Z",
  "selected_variant": {
    "config_name": "config-2",
    "variant_key": "rescue",
    "mode": "packet-up",
    "ip_family": "ipv4",
    "latency_ms": 321
  }
}
EOF
    out=$(self_check_status_summary_tsv)
    expected=$(printf "warning\trepair\t2026-03-07T12:00:00Z\tconfig-2\trescue\tpacket-up\tipv4\t321")
    [[ "$out" == "$expected" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self_check_post_action_verdict falls back to rescue and records warning" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_GROUP="xray"
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_KEYS="$tmp_dir/keys"
    SELF_CHECK_STATE_FILE="$tmp_dir/self-check.json"
    mkdir -p "$XRAY_KEYS"
    : > "$XRAY_CONFIG"
    cat > "$XRAY_BIN" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$XRAY_BIN"
    : > "$XRAY_KEYS/recommended-v4.json"
    : > "$XRAY_KEYS/rescue-v4.json"
    cat > "$XRAY_KEYS/clients.json" <<EOF
{
  "configs": [
    {
      "name": "config-1",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "mode": "auto",
          "xray_client_file_v4": "$XRAY_KEYS/recommended-v4.json"
        },
        {
          "key": "rescue",
          "mode": "packet-up",
          "xray_client_file_v4": "$XRAY_KEYS/rescue-v4.json"
        }
      ]
    }
  ]
}
EOF

    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    self_check_run_variant_probe() {
      local action="$1"
      local config_name="$2"
      local variant_key="$3"
      local mode="$4"
      local ip_family="$5"
      local raw_file="$6"
      if [[ "$variant_key" == "recommended" ]]; then
        jq -n --arg action "$action" --arg config_name "$config_name" --arg variant_key "$variant_key" --arg mode "$mode" --arg ip_family "$ip_family" --arg raw_file "$raw_file" '\''{
          checked_at: "2026-03-07T12:00:00Z",
          action: $action,
          config_name: $config_name,
          variant_key: $variant_key,
          mode: $mode,
          ip_family: $ip_family,
          raw_config_file: $raw_file,
          success: false,
          latency_ms: 0,
          selected_url: null,
          reason: "probe_failed",
          probe_results: []
        }'\''
      else
        jq -n --arg action "$action" --arg config_name "$config_name" --arg variant_key "$variant_key" --arg mode "$mode" --arg ip_family "$ip_family" --arg raw_file "$raw_file" '\''{
          checked_at: "2026-03-07T12:00:00Z",
          action: $action,
          config_name: $config_name,
          variant_key: $variant_key,
          mode: $mode,
          ip_family: $ip_family,
          raw_config_file: $raw_file,
          success: true,
          latency_ms: 87,
          selected_url: "https://cp.cloudflare.com/generate_204",
          reason: null,
          probe_results: []
        }'\''
      fi
    }

    self_check_post_action_verdict repair > /dev/null
    jq -e '\''.verdict == "warning"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''.selected_variant.variant_key == "rescue"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''(.attempted_variants | length) == 2'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" = "ok" ]]
}

@test "self_check_post_action_verdict falls back to secondary config when primary config fails" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_GROUP="xray"
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_KEYS="$tmp_dir/keys"
    SELF_CHECK_STATE_FILE="$tmp_dir/self-check.json"
    mkdir -p "$XRAY_KEYS"
    : > "$XRAY_CONFIG"
    cat > "$XRAY_BIN" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$XRAY_BIN"
    : > "$XRAY_KEYS/primary-recommended.json"
    : > "$XRAY_KEYS/primary-rescue.json"
    : > "$XRAY_KEYS/secondary-recommended.json"
    cat > "$XRAY_KEYS/clients.json" <<EOF
{
  "configs": [
    {
      "name": "config-1",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "mode": "auto",
          "xray_client_file_v4": "$XRAY_KEYS/primary-recommended.json"
        },
        {
          "key": "rescue",
          "mode": "packet-up",
          "xray_client_file_v4": "$XRAY_KEYS/primary-rescue.json"
        }
      ]
    },
    {
      "name": "config-2",
      "recommended_variant": "recommended",
      "variants": [
        {
          "key": "recommended",
          "mode": "auto",
          "xray_client_file_v4": "$XRAY_KEYS/secondary-recommended.json"
        }
      ]
    }
  ]
}
EOF

    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }
    self_check_run_variant_probe() {
      local action="$1"
      local config_name="$2"
      local variant_key="$3"
      local mode="$4"
      local ip_family="$5"
      local raw_file="$6"
      if [[ "$config_name" == "config-2" && "$variant_key" == "recommended" ]]; then
        jq -n --arg action "$action" --arg config_name "$config_name" --arg variant_key "$variant_key" --arg mode "$mode" --arg ip_family "$ip_family" --arg raw_file "$raw_file" '\''{
          checked_at: "2026-03-07T12:00:00Z",
          action: $action,
          config_name: $config_name,
          variant_key: $variant_key,
          mode: $mode,
          ip_family: $ip_family,
          raw_config_file: $raw_file,
          success: true,
          latency_ms: 144,
          selected_url: "https://cp.cloudflare.com/generate_204",
          reason: null,
          probe_results: []
        }'\''
      else
        jq -n --arg action "$action" --arg config_name "$config_name" --arg variant_key "$variant_key" --arg mode "$mode" --arg ip_family "$ip_family" --arg raw_file "$raw_file" '\''{
          checked_at: "2026-03-07T12:00:00Z",
          action: $action,
          config_name: $config_name,
          variant_key: $variant_key,
          mode: $mode,
          ip_family: $ip_family,
          raw_config_file: $raw_file,
          success: false,
          latency_ms: 0,
          selected_url: null,
          reason: "probe_failed",
          probe_results: []
        }'\''
      fi
    }

    self_check_post_action_verdict install > /dev/null
    jq -e '\''.verdict == "warning"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''.selected_variant.config_name == "config-2"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''.selected_variant.variant_key == "recommended"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''(.attempted_variants | length) == 3'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''(.reasons | any(test("primary-конфиг не прошёл self-check; используем запасной конфиг config-2")) )'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" = "ok" ]]
}

@test "self_check_post_action_verdict warns instead of failing when systemd is unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_GROUP="xray"
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_KEYS="$tmp_dir/keys"
    SELF_CHECK_STATE_FILE="$tmp_dir/self-check.json"
    mkdir -p "$XRAY_KEYS"
    : > "$XRAY_CONFIG"
    cat > "$XRAY_BIN" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$XRAY_BIN"

    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 1; }
    systemd_running() { return 1; }

    self_check_post_action_verdict install > /dev/null
    jq -e '\''.verdict == "warning"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''(.reasons | any(. == "systemd недоступен: transport-aware self-check пропущен"))'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''.selected_variant == null'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self_check_post_action_verdict skips transport probes on loopback installs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_GROUP="xray"
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_KEYS="$tmp_dir/keys"
    SELF_CHECK_STATE_FILE="$tmp_dir/self-check.json"
    SERVER_IP="127.0.0.1"
    mkdir -p "$XRAY_KEYS"
    : > "$XRAY_CONFIG"
    cat > "$XRAY_BIN" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$XRAY_BIN"

    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { return 0; }

    self_check_post_action_verdict install > /dev/null
    jq -e '\''.verdict == "warning"'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''(.reasons | any(. == "loopback install detected: transport-aware self-check пропущен"))'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e '\''.selected_variant == null'\'' "$SELF_CHECK_STATE_FILE" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self_check_stop_client_process force-kills stubborn client without hanging" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    bash -c '\''trap "" TERM; while :; do sleep 1; done'\'' > /dev/null 2>&1 &
    child_pid=$!
    start_epoch=$(date +%s)
    self_check_stop_client_process "$child_pid"
    elapsed=$(( $(date +%s) - start_epoch ))
    if kill -0 "$child_pid" 2> /dev/null; then
      echo "child-still-running"
      exit 1
    fi
    (( elapsed <= 20 ))
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
