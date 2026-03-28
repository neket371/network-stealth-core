#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154 # sourced config modules intentionally consume runtime globals from lib.sh/globals_contract.sh

xray_test_config_as_service_user() {
    local file="$1"

    if command -v runuser > /dev/null 2>&1; then
        if runuser -u "$XRAY_USER" -- "$XRAY_BIN" -test -c "$file"; then
            return 0
        fi
    fi

    if command -v sudo > /dev/null 2>&1; then
        if sudo -n -u "$XRAY_USER" -- "$XRAY_BIN" -test -c "$file"; then
            return 0
        fi
    fi

    # shellcheck disable=SC2016 # Intentional: $0/$1 expand at runtime inside su -c
    if su -s /bin/sh "$XRAY_USER" -c '"$0" -test -c "$1"' "$XRAY_BIN" "$file"; then
        return 0
    fi

    "$XRAY_BIN" -test -c "$file"
}

xray_config_test() {
    xray_test_config_as_service_user "$XRAY_CONFIG"
}

xray_config_test_file() {
    local file="$1"
    xray_test_config_as_service_user "$file"
}

xray_config_test_ok() {
    local file="${1:-$XRAY_CONFIG}"
    local test_output=""

    if ! test_output=$(xray_config_test_file "$file" 2>&1); then
        [[ -n "$test_output" ]] && printf '%s\n' "$test_output"
        return 1
    fi
    if [[ "$test_output" != *"Configuration OK"* ]]; then
        debug_file "xray -test succeeded without explicit 'Configuration OK' marker"
    fi
    return 0
}

set_temp_xray_config_permissions() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    chmod 640 "$file"
    if getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        chown "root:${XRAY_GROUP}" "$file" 2> /dev/null || true
    else
        chown root:root "$file" 2> /dev/null || true
        chmod 600 "$file" 2> /dev/null || true
    fi
}

create_temp_xray_config_file() {
    local tmp_base="${TMPDIR:-/tmp}"
    if [[ ! -d "$tmp_base" || ! -w "$tmp_base" ]]; then
        tmp_base="/tmp"
    fi

    local _old_umask
    local tmp_config
    _old_umask=$(umask)
    umask 077
    if ! tmp_config=$(mktemp "${tmp_base}/xray-config.XXXXXX.json"); then
        umask "$_old_umask"
        return 1
    fi
    umask "$_old_umask"
    printf '%s\n' "$tmp_config"
}

apply_validated_config() {
    local candidate_file="$1"
    if ! xray_config_test_ok "$candidate_file"; then
        log ERROR "Xray отклонил новую конфигурацию"
        rm -f "$candidate_file"
        return 1
    fi
    mv "$candidate_file" "$XRAY_CONFIG"
    chown "root:${XRAY_GROUP}" "$XRAY_CONFIG"
    chmod 640 "$XRAY_CONFIG"
    return 0
}

persist_managed_custom_domains_source() {
    local target="${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:-/etc/xray-reality/custom-domains.txt}"
    local -a custom_domains=()

    if [[ -n "${XRAY_CUSTOM_DOMAINS:-}" ]]; then
        mapfile -t custom_domains < <(load_domain_list "$XRAY_CUSTOM_DOMAINS")
    elif [[ -n "${XRAY_DOMAINS_FILE:-}" ]]; then
        mapfile -t custom_domains < <(load_domains_from_file "$XRAY_DOMAINS_FILE")
    else
        return 0
    fi

    if ((${#custom_domains[@]} < 1)); then
        log ERROR "Не удалось сохранить custom-domains state: список доменов пуст"
        return 1
    fi

    backup_file "$target"
    printf '%s\n' "${custom_domains[@]}" | atomic_write "$target" 0600
    XRAY_DOMAINS_FILE="$target"
    XRAY_CUSTOM_DOMAINS=""
    return 0
}

save_environment() {
    log STEP "Сохраняем окружение..."

    local installed_version install_date
    installed_version=$("$XRAY_BIN" version 2> /dev/null | head -1 | awk '{print $2}' || true)
    install_date=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "${XRAY_CUSTOM_DOMAINS:-}" || -n "${XRAY_DOMAINS_FILE:-}" ]]; then
        persist_managed_custom_domains_source || return 1
    fi

    backup_file "$XRAY_ENV"
    {
        printf '# Network Stealth Core %s Configuration\n' "$SCRIPT_VERSION"
        write_env_kv DOMAIN_PROFILE "${DOMAIN_PROFILE:-$DOMAIN_TIER}"
        write_env_kv XRAY_DOMAIN_PROFILE "${DOMAIN_PROFILE:-$DOMAIN_TIER}"
        write_env_kv DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv XRAY_DOMAIN_TIER "$DOMAIN_TIER"
        write_env_kv MUX_MODE "$MUX_MODE"
        write_env_kv TRANSPORT "$TRANSPORT"
        write_env_kv XRAY_TRANSPORT "$TRANSPORT"
        write_env_kv ADVANCED_MODE "$ADVANCED_MODE"
        write_env_kv XRAY_ADVANCED "$ADVANCED_MODE"
        write_env_kv PROGRESS_MODE "$PROGRESS_MODE"
        write_env_kv XRAY_PROGRESS_MODE "$PROGRESS_MODE"
        if [[ -n "${XRAY_DOMAINS_FILE:-}" ]]; then
            write_env_kv XRAY_DOMAINS_FILE "$XRAY_DOMAINS_FILE"
        fi
        write_env_kv XRAY_DATA_DIR "$XRAY_DATA_DIR"
        write_env_kv XRAY_ALLOW_CUSTOM_DATA_DIR "$XRAY_ALLOW_CUSTOM_DATA_DIR"
        write_env_kv MUX_ENABLED "$MUX_ENABLED"
        write_env_kv MUX_CONCURRENCY "$MUX_CONCURRENCY"
        write_env_kv SHORT_ID_BYTES_MIN "$SHORT_ID_BYTES_MIN"
        write_env_kv SHORT_ID_BYTES_MAX "$SHORT_ID_BYTES_MAX"
        write_env_kv DOMAIN_CHECK "$DOMAIN_CHECK"
        write_env_kv DOMAIN_CHECK_TIMEOUT "$DOMAIN_CHECK_TIMEOUT"
        write_env_kv DOMAIN_CHECK_PARALLELISM "$DOMAIN_CHECK_PARALLELISM"
        write_env_kv REALITY_TEST_PORTS "$REALITY_TEST_PORTS"
        write_env_kv SKIP_REALITY_CHECK "$SKIP_REALITY_CHECK"
        write_env_kv DOMAIN_HEALTH_FILE "$DOMAIN_HEALTH_FILE"
        write_env_kv DOMAIN_HEALTH_PROBE_TIMEOUT "$DOMAIN_HEALTH_PROBE_TIMEOUT"
        write_env_kv DOMAIN_HEALTH_RATE_LIMIT_MS "$DOMAIN_HEALTH_RATE_LIMIT_MS"
        write_env_kv DOMAIN_HEALTH_MAX_PROBES "$DOMAIN_HEALTH_MAX_PROBES"
        write_env_kv DOMAIN_HEALTH_RANKING "$DOMAIN_HEALTH_RANKING"
        write_env_kv HEALTH_CHECK_INTERVAL "$HEALTH_CHECK_INTERVAL"
        write_env_kv SELF_CHECK_ENABLED "$SELF_CHECK_ENABLED"
        write_env_kv SELF_CHECK_URLS "$SELF_CHECK_URLS"
        write_env_kv SELF_CHECK_TIMEOUT_SEC "$SELF_CHECK_TIMEOUT_SEC"
        write_env_kv SELF_CHECK_STATE_FILE "$SELF_CHECK_STATE_FILE"
        write_env_kv SELF_CHECK_HISTORY_FILE "$SELF_CHECK_HISTORY_FILE"
        write_env_kv LOG_RETENTION_DAYS "$LOG_RETENTION_DAYS"
        write_env_kv LOG_MAX_SIZE_MB "$LOG_MAX_SIZE_MB"
        write_env_kv HEALTH_LOG "$HEALTH_LOG"
        write_env_kv XRAY_POLICY "$XRAY_POLICY"
        write_env_kv XRAY_DOMAIN_CATALOG_FILE "$XRAY_DOMAIN_CATALOG_FILE"
        write_env_kv MEASUREMENTS_DIR "$MEASUREMENTS_DIR"
        write_env_kv MEASUREMENTS_SUMMARY_FILE "$MEASUREMENTS_SUMMARY_FILE"
        write_env_kv MEASUREMENTS_ROTATION_STATE_FILE "$MEASUREMENTS_ROTATION_STATE_FILE"
        write_env_kv DOMAIN_QUARANTINE_FAIL_STREAK "$DOMAIN_QUARANTINE_FAIL_STREAK"
        write_env_kv DOMAIN_QUARANTINE_COOLDOWN_MIN "$DOMAIN_QUARANTINE_COOLDOWN_MIN"
        write_env_kv PRIMARY_DOMAIN_MODE "$PRIMARY_DOMAIN_MODE"
        write_env_kv PRIMARY_PIN_DOMAIN "$PRIMARY_PIN_DOMAIN"
        write_env_kv PRIMARY_ADAPTIVE_TOP_N "$PRIMARY_ADAPTIVE_TOP_N"
        write_env_kv DOWNLOAD_HOST_ALLOWLIST "$DOWNLOAD_HOST_ALLOWLIST"
        write_env_kv GH_PROXY_BASE "$GH_PROXY_BASE"
        write_env_kv KEEP_LOCAL_BACKUPS "$KEEP_LOCAL_BACKUPS"
        write_env_kv REUSE_EXISTING "$REUSE_EXISTING"
        write_env_kv AUTO_ROLLBACK "$AUTO_ROLLBACK"
        write_env_kv XRAY_VERSION "$XRAY_VERSION"
        write_env_kv XRAY_MIRRORS "$XRAY_MIRRORS"
        write_env_kv MINISIGN_MIRRORS "$MINISIGN_MIRRORS"
        write_env_kv XRAY_GEO_DIR "$XRAY_GEO_DIR"
        write_env_kv XRAY_GEOIP_URL "$XRAY_GEOIP_URL"
        write_env_kv XRAY_GEOSITE_URL "$XRAY_GEOSITE_URL"
        write_env_kv XRAY_GEOIP_SHA256_URL "$XRAY_GEOIP_SHA256_URL"
        write_env_kv XRAY_GEOSITE_SHA256_URL "$XRAY_GEOSITE_SHA256_URL"
        write_env_kv QR_ENABLED "$QR_ENABLED"
        write_env_kv XRAY_CLIENT_MIN_VERSION "$XRAY_CLIENT_MIN_VERSION"
        write_env_kv XRAY_DIRECT_FLOW "$XRAY_DIRECT_FLOW"
        write_env_kv STEALTH_CONTRACT_VERSION "$STEALTH_CONTRACT_VERSION"
        write_env_kv BROWSER_DIALER_ENV_NAME "$BROWSER_DIALER_ENV_NAME"
        write_env_kv XRAY_BROWSER_DIALER_ADDRESS "$XRAY_BROWSER_DIALER_ADDRESS"
        write_env_kv REPLAN "$REPLAN"
        write_env_kv AUTO_UPDATE "$AUTO_UPDATE"
        write_env_kv AUTO_UPDATE_ONCALENDAR "$AUTO_UPDATE_ONCALENDAR"
        write_env_kv AUTO_UPDATE_RANDOM_DELAY "$AUTO_UPDATE_RANDOM_DELAY"
        write_env_kv ALLOW_INSECURE_SHA256 "$ALLOW_INSECURE_SHA256"
        write_env_kv ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP "$ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP"
        write_env_kv REQUIRE_MINISIGN "$REQUIRE_MINISIGN"
        write_env_kv ALLOW_NO_SYSTEMD "$ALLOW_NO_SYSTEMD"
        write_env_kv GEO_VERIFY_HASH "$GEO_VERIFY_HASH"
        write_env_kv GEO_VERIFY_STRICT "$GEO_VERIFY_STRICT"
        write_env_kv XRAY_SCRIPT_PATH "$XRAY_SCRIPT_PATH"
        write_env_kv XRAY_UPDATE_SCRIPT "$XRAY_UPDATE_SCRIPT"
        write_env_kv NUM_CONFIGS "$NUM_CONFIGS"
        write_env_kv XRAY_NUM_CONFIGS "$NUM_CONFIGS"
        write_env_kv SPIDER_MODE "${SPIDER_MODE:-false}"
        write_env_kv XRAY_SPIDER_MODE "$SPIDER_MODE"
        write_env_kv START_PORT "$START_PORT"
        write_env_kv XRAY_START_PORT "$START_PORT"
        write_env_kv INSTALLED_VERSION "$installed_version"
        write_env_kv INSTALL_DATE "$install_date"
        write_env_kv XRAY_SOURCE_KIND "${XRAY_SOURCE_KIND:-}"
        write_env_kv XRAY_SOURCE_REF "${XRAY_SOURCE_REF:-}"
        write_env_kv XRAY_SOURCE_COMMIT "${XRAY_SOURCE_COMMIT:-}"
        write_env_kv SERVER_IP "$SERVER_IP"
        write_env_kv SERVER_IP6 "$SERVER_IP6"
    } | atomic_write "$XRAY_ENV" 0600

    log OK "Окружение сохранено в $XRAY_ENV"
}
