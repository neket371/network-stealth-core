#!/usr/bin/env bash
# shellcheck shell=bash

load_config_file() {
    local file="$1"
    local previous_measurements_summary_file="${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
    if [[ -z "$file" ]]; then
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        log WARN "Конфиг не найден: $file"
        return 0
    fi
    if [[ "$file" == *.json ]]; then
        log INFO "Загружаем policy: $file"
        load_policy_file "$file"
        return 0
    fi
    log INFO "Загружаем конфиг: $file"
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" != *"="* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ ${#value} -ge 2 ]]; then
            local first_char="${value:0:1}"
            local last_char="${value: -1}"
            if [[ ("$first_char" == '"' && "$last_char" == '"') || ("$first_char" == "'" && "$last_char" == "'") ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi
        case "$key" in
            XRAY_DOMAIN_TIER | XRAY_DOMAIN_PROFILE | XRAY_NUM_CONFIGS | XRAY_SPIDER_MODE | XRAY_START_PORT | XRAY_PROGRESS_MODE | XRAY_ADVANCED | DOMAIN_PROFILE | DOMAIN_TIER | NUM_CONFIGS | SPIDER_MODE | START_PORT | PROGRESS_MODE | ADVANCED_MODE | XRAY_TRANSPORT | TRANSPORT | MUX_MODE | MUX_CONCURRENCY_MIN | MUX_CONCURRENCY_MAX | GRPC_IDLE_TIMEOUT_MIN | GRPC_IDLE_TIMEOUT_MAX | GRPC_HEALTH_TIMEOUT_MIN | GRPC_HEALTH_TIMEOUT_MAX | TCP_KEEPALIVE_MIN | TCP_KEEPALIVE_MAX | SHORT_ID_BYTES_MIN | SHORT_ID_BYTES_MAX | KEEP_LOCAL_BACKUPS | MAX_BACKUPS | REUSE_EXISTING | AUTO_ROLLBACK | XRAY_VERSION | XRAY_MIRRORS | MINISIGN_MIRRORS | QR_ENABLED | AUTO_UPDATE | AUTO_UPDATE_ONCALENDAR | AUTO_UPDATE_RANDOM_DELAY | ALLOW_INSECURE_SHA256 | ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP | REQUIRE_MINISIGN | ALLOW_NO_SYSTEMD | GEO_VERIFY_HASH | GEO_VERIFY_STRICT | XRAY_CUSTOM_DOMAINS | XRAY_DOMAINS_FILE | XRAY_SNI_POOLS_FILE | XRAY_TRANSPORT_ENDPOINTS_FILE | XRAY_GRPC_SERVICES_FILE | XRAY_TIERS_FILE | XRAY_DATA_DIR | XRAY_ALLOW_CUSTOM_DATA_DIR | XRAY_GEO_DIR | XRAY_SCRIPT_PATH | XRAY_UPDATE_SCRIPT | DOMAIN_CHECK | DOMAIN_CHECK_TIMEOUT | DOMAIN_CHECK_PARALLELISM | REALITY_TEST_PORTS | SKIP_REALITY_CHECK | DOMAIN_HEALTH_FILE | DOMAIN_HEALTH_PROBE_TIMEOUT | DOMAIN_HEALTH_RATE_LIMIT_MS | DOMAIN_HEALTH_MAX_PROBES | DOMAIN_HEALTH_RANKING | DOMAIN_QUARANTINE_FAIL_STREAK | DOMAIN_QUARANTINE_COOLDOWN_MIN | PRIMARY_DOMAIN_MODE | PRIMARY_PIN_DOMAIN | PRIMARY_ADAPTIVE_TOP_N | DOWNLOAD_HOST_ALLOWLIST | GH_PROXY_BASE | DOWNLOAD_TIMEOUT | DOWNLOAD_RETRIES | DOWNLOAD_RETRY_DELAY | SERVER_IP | SERVER_IP6 | DRY_RUN | VERBOSE | HEALTH_CHECK_INTERVAL | SELF_CHECK_ENABLED | SELF_CHECK_URLS | SELF_CHECK_TIMEOUT_SEC | SELF_CHECK_STATE_FILE | SELF_CHECK_HISTORY_FILE | LOG_RETENTION_DAYS | LOG_MAX_SIZE_MB | HEALTH_LOG | XRAY_POLICY | XRAY_DOMAIN_CATALOG_FILE | MEASUREMENTS_DIR | MEASUREMENTS_SUMMARY_FILE | MEASUREMENTS_ROTATION_STATE_FILE | XRAY_CLIENT_MIN_VERSION | XRAY_DIRECT_FLOW | BROWSER_DIALER_ENV_NAME | XRAY_BROWSER_DIALER_ADDRESS | REPLAN)
                printf -v "$key" '%s' "$value"
                ;;
            *) ;;
        esac
    done < "$file"
    if declare -F sync_measurements_rotation_state_file_contract > /dev/null 2>&1; then
        sync_measurements_rotation_state_file_contract "$previous_measurements_summary_file"
    fi
}

load_runtime_identity_defaults() {
    local file="${1:-$XRAY_ENV}"
    [[ -n "$file" && -f "$file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *"="* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ ${#value} -ge 2 ]]; then
            local first_char="${value:0:1}"
            local last_char="${value: -1}"
            if [[ ("$first_char" == '"' && "$last_char" == '"') || ("$first_char" == "'" && "$last_char" == "'") ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi

        case "$key" in
            SERVER_IP)
                [[ -n "${SERVER_IP:-}" || -z "$value" ]] || SERVER_IP="$value"
                ;;
            SERVER_IP6)
                [[ -n "${SERVER_IP6:-}" || -z "$value" ]] || SERVER_IP6="$value"
                ;;
            DOMAIN_PROFILE | XRAY_DOMAIN_PROFILE)
                [[ -n "${DOMAIN_PROFILE:-}" || -z "$value" ]] || DOMAIN_PROFILE="$value"
                ;;
            DOMAIN_TIER | XRAY_DOMAIN_TIER)
                [[ -n "${DOMAIN_TIER:-}" || -z "$value" ]] || DOMAIN_TIER="$value"
                ;;
            SPIDER_MODE | XRAY_SPIDER_MODE)
                [[ -n "${SPIDER_MODE:-}" || -z "$value" ]] || SPIDER_MODE="$value"
                ;;
            START_PORT | XRAY_START_PORT)
                [[ -n "${START_PORT:-}" || -z "$value" ]] || START_PORT="$value"
                ;;
            NUM_CONFIGS | XRAY_NUM_CONFIGS)
                [[ -n "${NUM_CONFIGS:-}" || -z "$value" ]] || NUM_CONFIGS="$value"
                ;;
            XRAY_SOURCE_KIND)
                [[ -n "${XRAY_SOURCE_KIND:-}" || -z "$value" ]] || XRAY_SOURCE_KIND="$value"
                ;;
            XRAY_SOURCE_REF)
                [[ -n "${XRAY_SOURCE_REF:-}" || -z "$value" ]] || XRAY_SOURCE_REF="$value"
                ;;
            XRAY_SOURCE_COMMIT)
                [[ -n "${XRAY_SOURCE_COMMIT:-}" || -z "$value" ]] || XRAY_SOURCE_COMMIT="$value"
                ;;
            *) ;;
        esac
    done < "$file"
}
