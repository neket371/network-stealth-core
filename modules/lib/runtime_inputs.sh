#!/usr/bin/env bash
# shellcheck shell=bash

: "${ACTION:=install}"
: "${DOMAIN_TIER:=tier_ru}"
: "${NUM_CONFIGS:=5}"
: "${START_PORT:=443}"
: "${SPIDER_MODE:=true}"
: "${TRANSPORT:=xhttp}"
: "${ADVANCED_MODE:=false}"
: "${AUTO_UPDATE:=true}"
: "${SERVER_IP:=}"
: "${SERVER_IP6:=}"
: "${PROGRESS_MODE:=auto}"
: "${XRAY_PROGRESS_MODE:=auto}"
: "${XRAY_CONFIG:=/etc/xray/config.json}"
: "${XRAY_ENV:=/etc/xray-reality/config.env}"
: "${XRAY_POLICY:=/etc/xray-reality/policy.json}"
: "${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:=/etc/xray-reality/custom-domains.txt}"
: "${XRAY_SCRIPT_PATH:=/usr/local/bin/xray-reality.sh}"
: "${XRAY_UPDATE_SCRIPT:=/usr/local/bin/xray-reality-update.sh}"
: "${MINISIGN_KEY:=/etc/xray/minisign.pub}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_MIRRORS:=}"
: "${MINISIGN_MIRRORS:=}"
: "${DOWNLOAD_HOST_ALLOWLIST:=github.com,api.github.com,objects.githubusercontent.com,raw.githubusercontent.com,release-assets.githubusercontent.com,ghproxy.com}"
: "${SELF_CHECK_ENABLED:=true}"
: "${SELF_CHECK_URLS:=https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204}"
: "${REALITY_TEST_PORTS:=443,8443,2053,2083,2087,2096}"
: "${BOLD:=}"
: "${CYAN:=}"
: "${NC:=}"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        log ERROR "Требуется команда: $cmd"
        exit 1
    fi
}

get_query_param() {
    local query="$1"
    local key="$2"
    local pair
    local value
    IFS='&' read -r -a pairs <<< "$query"
    for pair in "${pairs[@]}"; do
        if [[ "$pair" == "${key}="* ]]; then
            value="${pair#"${key}"=}"
            url_decode_query_component "$value"
            return 0
        fi
    done
    return 1
}

url_decode_query_component() {
    local input="${1:-}"
    local out="" hex ch
    local i=0
    local n=${#input}

    while ((i < n)); do
        ch="${input:i:1}"
        if [[ "$ch" == "%" && $((i + 2)) -lt n ]]; then
            hex="${input:i+1:2}"
            if [[ "$hex" =~ ^[0-9A-Fa-f]{2}$ ]]; then
                printf -v ch '\\x%s' "$hex"
                out+=$(printf '%b' "$ch")
                i=$((i + 3))
                continue
            fi
        fi
        if [[ "$ch" == "+" ]]; then
            out+=" "
        else
            out+="$ch"
        fi
        i=$((i + 1))
    done
    printf '%s\n' "$out"
}

dry_run_summary() {
    local box_width box_top box_bottom box_line
    box_width=$(ui_box_width_for_lines 60 90 "DRY-RUN: изменения НЕ применяются")
    box_top=$(ui_box_border_string top "$box_width")
    box_bottom=$(ui_box_border_string bottom "$box_width")
    box_line=$(ui_box_line_string "DRY-RUN: изменения НЕ применяются" "$box_width")

    echo ""
    echo -e "${BOLD}${CYAN}${box_top}${NC}"
    echo -e "${BOLD}${CYAN}${box_line}${NC}"
    echo -e "${BOLD}${CYAN}${box_bottom}${NC}"
    echo ""

    echo -e "${BOLD}Действие:${NC} $ACTION"
    echo ""

    case "$ACTION" in
        install)
            local limit
            limit=$(max_configs_for_tier "$DOMAIN_TIER")
            echo -e "${BOLD}Параметры установки:${NC}"
            echo "  Профиль:       $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
            echo "  Кол-во ключей: ${NUM_CONFIGS} (лимит: ${limit})"
            echo "  Начальный порт: ${START_PORT}"
            echo "  Spider Mode:   ${SPIDER_MODE}"
            echo "  Transport:     ${TRANSPORT}"
            echo "  Advanced UX:   ${ADVANCED_MODE}"
            echo "  MUX:           ${MUX_MODE}"
            echo "  Auto-update:   ${AUTO_UPDATE}"
            echo "  IPv4:          ${SERVER_IP:-auto-detect}"
            echo "  IPv6:          ${SERVER_IP6:-auto-detect}"
            echo ""
            echo -e "${BOLD}Шаги выполнения:${NC}"
            echo "  1. Определение ОС и установка зависимостей"
            echo "  2. Проверка свободного места на диске"
            echo "  3. Создание пользователя xray"
            echo "  4. Установка minisign + Xray-core (с верификацией)"
            echo "  5. Настройка доменов и генерация ключей"
            echo "  6. Сборка конфигурации (xhttp + Reality)"
            echo "  7. Создание systemd-сервиса + файрвол"
            echo "  8. Настройка health-мониторинга + auto-update"
            echo "  9. Генерация клиентских конфигов + raw xray artifacts"
            echo "  10. Transport-aware self-check и capability matrix"
            ;;
        add-clients | add-keys)
            echo -e "${BOLD}Шаги:${NC}"
            echo "  1. Загрузка текущей конфигурации"
            echo "  2. Генерация новых ключей X25519"
            echo "  3. Выделение портов и создание inbounds"
            echo "  4. Обновление файрвола"
            echo "  5. Перезапуск Xray"
            ;;
        update)
            echo -e "${BOLD}Шаги:${NC}"
            echo "  1. Обновление зависимостей"
            echo "  2. Скачивание новой версии Xray-core"
            echo "  3. Криптографическая проверка (minisign + SHA256)"
            echo "  4. Перезапуск сервиса"
            ;;
        repair)
            echo -e "${BOLD}Шаги:${NC}"
            echo "  1. Проверка/установка зависимостей"
            echo "  2. Восстановление systemd unit + timers"
            echo "  3. Повторная настройка firewall и автозадач"
            echo "  4. Пересборка клиентских артефактов при рассинхроне"
            echo "  5. Финальная self-check с verdict"
            ;;
        diagnose)
            echo -e "${BOLD}Шаги:${NC} сбор диагностики (systemd, сеть, ресурсы)"
            ;;
        doctor)
            echo -e "${BOLD}Шаги:${NC} короткий verdict по runtime, self-check и field summary"
            ;;
        rollback)
            echo -e "${BOLD}Шаги:${NC} восстановление из бэкапа ${ROLLBACK_DIR:-последнего}"
            ;;
        uninstall)
            echo -e "${BOLD}Шаги:${NC} полное удаление (сервисы, конфиги, ключи, пользователь, файрвол)"
            ;;
        *)
            echo -e "${BOLD}Шаги:${NC} ${ACTION}"
            ;;
    esac
    echo ""
}

normalize_numeric_range_or_default() {
    local var_name="$1"
    local min="$2"
    local max="$3"
    local default="$4"
    local current="${!var_name:-}"

    if [[ ! "$current" =~ ^[0-9]+$ ]] || ((current < min || current > max)); then
        log WARN "Некорректный ${var_name}: ${current} (используем ${default})"
        printf -v "$var_name" '%s' "$default"
    fi
}

strict_validate_numeric_range() {
    local var_name="$1"
    local min="$2"
    local max="$3"
    local current="${!var_name:-}"

    if [[ ! "$current" =~ ^[0-9]+$ ]] || ((current < min || current > max)); then
        log ERROR "Некорректный ${var_name}: ${current}"
        return 1
    fi
    return 0
}

runtime_common_range_specs() {
    cat << 'EOF'
MAX_BACKUPS 1 1000 10
HEALTH_CHECK_INTERVAL 10 86400 120
LOG_RETENTION_DAYS 1 3650 30
LOG_MAX_SIZE_MB 1 1024 10
DOMAIN_CHECK_TIMEOUT 1 30 3
DOMAIN_CHECK_PARALLELISM 1 128 16
DOMAIN_HEALTH_PROBE_TIMEOUT 1 15 2
DOMAIN_HEALTH_RATE_LIMIT_MS 0 10000 250
DOMAIN_HEALTH_MAX_PROBES 1 200 20
DOMAIN_QUARANTINE_FAIL_STREAK 1 50 4
DOMAIN_QUARANTINE_COOLDOWN_MIN 1 10080 120
PRIMARY_ADAPTIVE_TOP_N 1 50 5
EOF
}

normalize_runtime_common_ranges() {
    local var min max default
    while read -r var min max default; do
        [[ -n "$var" ]] || continue
        normalize_numeric_range_or_default "$var" "$min" "$max" "$default"
    done < <(runtime_common_range_specs)
}

strict_validate_runtime_common_ranges() {
    local var min max default
    while read -r var min max default; do
        [[ -n "$var" ]] || continue
        strict_validate_numeric_range "$var" "$min" "$max" || return 1
    done < <(runtime_common_range_specs)
    return 0
}

normalize_runtime_schedule_settings() {
    if ! is_valid_systemd_duration "$AUTO_UPDATE_RANDOM_DELAY"; then
        log WARN "Некорректный AUTO_UPDATE_RANDOM_DELAY: $AUTO_UPDATE_RANDOM_DELAY (используем 1h)"
        AUTO_UPDATE_RANDOM_DELAY="1h"
    fi
    if ! is_valid_systemd_oncalendar "$AUTO_UPDATE_ONCALENDAR"; then
        log WARN "Некорректный AUTO_UPDATE_ONCALENDAR: $AUTO_UPDATE_ONCALENDAR (используем weekly)"
        AUTO_UPDATE_ONCALENDAR="weekly"
    fi
}

normalize_progress_mode() {
    local mode="${PROGRESS_MODE:-${XRAY_PROGRESS_MODE:-auto}}"
    mode=$(trim_ws "${mode,,}")
    [[ -z "$mode" ]] && mode="auto"
    case "$mode" in
        auto | bar | plain | none | off) ;;
        *)
            log WARN "Некорректный PROGRESS_MODE: ${mode} (используем auto)"
            mode="auto"
            ;;
    esac
    [[ "$mode" == "off" ]] && mode="none"

    PROGRESS_MODE="$mode"
    XRAY_PROGRESS_MODE="$mode"
    PROGRESS_RENDER_MODE=""
    PROGRESS_RENDER_MODE_SOURCE=""
    PROGRESS_LAST_PERCENT=-1
    : "${PROGRESS_RENDER_MODE}" "${PROGRESS_RENDER_MODE_SOURCE}" "${PROGRESS_LAST_PERCENT}"
}

strict_validate_progress_mode() {
    local mode="${PROGRESS_MODE:-${XRAY_PROGRESS_MODE:-auto}}"
    mode=$(trim_ws "${mode,,}")
    [[ -z "$mode" ]] && mode="auto"
    case "$mode" in
        auto | bar | plain | none | off) return 0 ;;
        *)
            log ERROR "Некорректный PROGRESS_MODE: ${mode} (ожидается auto|bar|plain|none)"
            return 1
            ;;
    esac
}

strict_validate_runtime_schedule_settings() {
    if ! is_valid_systemd_oncalendar "$AUTO_UPDATE_ONCALENDAR"; then
        log ERROR "Некорректный AUTO_UPDATE_ONCALENDAR: ${AUTO_UPDATE_ONCALENDAR}"
        return 1
    fi
    if ! is_valid_systemd_duration "$AUTO_UPDATE_RANDOM_DELAY"; then
        log ERROR "Некорректный AUTO_UPDATE_RANDOM_DELAY: ${AUTO_UPDATE_RANDOM_DELAY}"
        return 1
    fi
    return 0
}

normalize_primary_domain_controls() {
    PRIMARY_DOMAIN_MODE="${PRIMARY_DOMAIN_MODE,,}"
    case "$PRIMARY_DOMAIN_MODE" in
        adaptive | pinned) ;;
        *)
            log WARN "Некорректный PRIMARY_DOMAIN_MODE: $PRIMARY_DOMAIN_MODE (используем adaptive)"
            PRIMARY_DOMAIN_MODE="adaptive"
            ;;
    esac

    local default_pin=""
    if [[ -n "$XRAY_TIERS_FILE" && -f "$XRAY_TIERS_FILE" ]]; then
        default_pin=$(load_tier_domains_from_file "$XRAY_TIERS_FILE" "priority" | head -n 1 || true)
        if [[ -z "$default_pin" ]]; then
            local selected_tier
            selected_tier="${DOMAIN_TIER:-tier_ru}"
            if ! selected_tier=$(normalize_domain_tier "$selected_tier" 2> /dev/null); then
                selected_tier="tier_ru"
            fi
            default_pin=$(load_tier_domains_from_file "$XRAY_TIERS_FILE" "$selected_tier" | head -n 1 || true)
        fi
    fi

    if [[ "$PRIMARY_DOMAIN_MODE" == "pinned" ]]; then
        if [[ -n "$PRIMARY_PIN_DOMAIN" ]] && is_valid_domain "$PRIMARY_PIN_DOMAIN"; then
            return 0
        fi
        if [[ -n "$default_pin" ]] && is_valid_domain "$default_pin"; then
            log WARN "Некорректный PRIMARY_PIN_DOMAIN: ${PRIMARY_PIN_DOMAIN:-<empty>} (используем ${default_pin})"
            PRIMARY_PIN_DOMAIN="$default_pin"
        else
            log WARN "Некорректный PRIMARY_PIN_DOMAIN: ${PRIMARY_PIN_DOMAIN:-<empty>} (будет выбран первый доступный домен)"
            PRIMARY_PIN_DOMAIN=""
        fi
        return 0
    fi

    if [[ -n "$PRIMARY_PIN_DOMAIN" ]] && ! is_valid_domain "$PRIMARY_PIN_DOMAIN"; then
        log WARN "Некорректный PRIMARY_PIN_DOMAIN: ${PRIMARY_PIN_DOMAIN} (очищено)"
        PRIMARY_PIN_DOMAIN=""
    fi
}

strict_validate_primary_domain_controls() {
    case "${PRIMARY_DOMAIN_MODE,,}" in
        adaptive | pinned) ;;
        *)
            log ERROR "Некорректный PRIMARY_DOMAIN_MODE: ${PRIMARY_DOMAIN_MODE}"
            return 1
            ;;
    esac
    if [[ -n "$PRIMARY_PIN_DOMAIN" ]] && ! is_valid_domain "$PRIMARY_PIN_DOMAIN"; then
        log ERROR "Некорректный PRIMARY_PIN_DOMAIN: ${PRIMARY_PIN_DOMAIN}"
        return 1
    fi
    return 0
}

strict_validate_runtime_safe_vars() {
    local var
    local -a safe_vars=(
        XRAY_BIN XRAY_CONFIG XRAY_ENV XRAY_MANAGED_CUSTOM_DOMAINS_FILE XRAY_KEYS XRAY_BACKUP XRAY_LOGS XRAY_HOME
        XRAY_DATA_DIR XRAY_GEO_DIR XRAY_SCRIPT_PATH XRAY_UPDATE_SCRIPT MINISIGN_KEY
        XRAY_CONFIG_FILE DOWNLOAD_HOST_ALLOWLIST XRAY_MIRRORS MINISIGN_MIRRORS
        GH_PROXY_BASE XRAY_SOURCE_KIND XRAY_SOURCE_REF XRAY_SOURCE_COMMIT
        XRAY_GEOIP_URL XRAY_GEOSITE_URL XRAY_GEOIP_SHA256_URL XRAY_GEOSITE_SHA256_URL
        DOMAIN_HEALTH_FILE HEALTH_LOG SELF_CHECK_URLS SELF_CHECK_STATE_FILE SELF_CHECK_HISTORY_FILE
        AUTO_UPDATE_ONCALENDAR AUTO_UPDATE_RANDOM_DELAY
        HEALTH_CHECK_INTERVAL SELF_CHECK_TIMEOUT_SEC LOG_RETENTION_DAYS LOG_MAX_SIZE_MB
        PROGRESS_MODE XRAY_PROGRESS_MODE XRAY_POLICY XRAY_DOMAIN_CATALOG_FILE
        MEASUREMENTS_DIR MEASUREMENTS_SUMMARY_FILE MEASUREMENTS_ROTATION_STATE_FILE XRAY_CLIENT_MIN_VERSION
        XRAY_DIRECT_FLOW BROWSER_DIALER_ENV_NAME XRAY_BROWSER_DIALER_ADDRESS
    )

    for var in "${safe_vars[@]}"; do
        validate_no_control_chars "$var" "${!var:-}" || return 1
    done
}

strict_validate_runtime_action_paths() {
    local action="${1:-$ACTION}"
    case "$action" in
        install | add-clients | add-keys | update | repair | diagnose | rollback | uninstall)
            validate_destructive_runtime_paths || return 1
            ;;
        *) ;;
    esac
}

strict_validate_runtime_file_contracts() {
    validate_safe_executable_path "XRAY_BIN" "$XRAY_BIN" || return 1
    validate_safe_executable_path "XRAY_SCRIPT_PATH" "$XRAY_SCRIPT_PATH" || return 1
    validate_safe_executable_path "XRAY_UPDATE_SCRIPT" "$XRAY_UPDATE_SCRIPT" || return 1
    validate_safe_executable_path "XRAY_CONFIG" "$XRAY_CONFIG" || return 1
    if [[ -n "$HEALTH_LOG" ]]; then
        if [[ "$HEALTH_LOG" != /* ]] || [[ ! "$HEALTH_LOG" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "HEALTH_LOG содержит небезопасные символы: ${HEALTH_LOG}"
            return 1
        fi
    fi
    if [[ -n "$SELF_CHECK_STATE_FILE" ]]; then
        if [[ "$SELF_CHECK_STATE_FILE" != /* ]] || [[ ! "$SELF_CHECK_STATE_FILE" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "SELF_CHECK_STATE_FILE содержит небезопасные символы: ${SELF_CHECK_STATE_FILE}"
            return 1
        fi
    fi
    if [[ -n "$SELF_CHECK_HISTORY_FILE" ]]; then
        if [[ "$SELF_CHECK_HISTORY_FILE" != /* ]] || [[ ! "$SELF_CHECK_HISTORY_FILE" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "SELF_CHECK_HISTORY_FILE содержит небезопасные символы: ${SELF_CHECK_HISTORY_FILE}"
            return 1
        fi
    fi
    if [[ -n "$MEASUREMENTS_SUMMARY_FILE" ]]; then
        if [[ "$MEASUREMENTS_SUMMARY_FILE" != /* ]] || [[ ! "$MEASUREMENTS_SUMMARY_FILE" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "MEASUREMENTS_SUMMARY_FILE содержит небезопасные символы: ${MEASUREMENTS_SUMMARY_FILE}"
            return 1
        fi
    fi
    if [[ -n "$MEASUREMENTS_ROTATION_STATE_FILE" ]]; then
        if [[ "$MEASUREMENTS_ROTATION_STATE_FILE" != /* ]] || [[ ! "$MEASUREMENTS_ROTATION_STATE_FILE" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "MEASUREMENTS_ROTATION_STATE_FILE содержит небезопасные символы: ${MEASUREMENTS_ROTATION_STATE_FILE}"
            return 1
        fi
    fi
    if [[ -n "$MEASUREMENTS_DIR" ]]; then
        if [[ "$MEASUREMENTS_DIR" != /* ]] || [[ ! "$MEASUREMENTS_DIR" =~ ^/[A-Za-z0-9._/+:-]+$ ]]; then
            log ERROR "MEASUREMENTS_DIR содержит небезопасные символы: ${MEASUREMENTS_DIR}"
            return 1
        fi
    fi
}

strict_validate_runtime_download_contracts() {
    local url_var
    for url_var in XRAY_GEOIP_URL XRAY_GEOSITE_URL XRAY_GEOIP_SHA256_URL XRAY_GEOSITE_SHA256_URL; do
        if [[ -n "${!url_var:-}" ]] && ! validate_curl_target "${!url_var}" true; then
            log ERROR "${url_var}: требуется HTTPS URL из DOWNLOAD_HOST_ALLOWLIST"
            return 1
        fi
    done
    if [[ -n "${GH_PROXY_BASE:-}" ]] && ! is_valid_https_url "$GH_PROXY_BASE"; then
        log ERROR "GH_PROXY_BASE: требуется HTTPS URL"
        return 1
    fi
    validate_mirror_list_urls "$XRAY_MIRRORS" "XRAY_MIRRORS" || return 1
    validate_mirror_list_urls "$MINISIGN_MIRRORS" "MINISIGN_MIRRORS" || return 1

    local host
    while read -r host; do
        host=$(trim_ws "${host,,}")
        [[ -z "$host" ]] && continue
        if [[ ! "$host" =~ ^[a-z0-9.-]+$ ]]; then
            log ERROR "DOWNLOAD_HOST_ALLOWLIST содержит невалидный хост: ${host}"
            return 1
        fi
    done < <(split_list "$DOWNLOAD_HOST_ALLOWLIST")
}

strict_validate_runtime_network_identity() {
    if [[ -n "${SERVER_IP:-}" ]] && ! is_valid_ipv4 "$SERVER_IP"; then
        log ERROR "Некорректный SERVER_IP: ${SERVER_IP}"
        return 1
    fi
    if [[ -n "${SERVER_IP6:-}" ]] && ! is_valid_ipv6 "$SERVER_IP6"; then
        log ERROR "Некорректный SERVER_IP6: ${SERVER_IP6}"
        return 1
    fi
}

strict_validate_runtime_probe_settings() {
    strict_validate_runtime_schedule_settings || return 1
    strict_validate_progress_mode || return 1
    strict_validate_runtime_common_ranges || return 1

    case "${SELF_CHECK_ENABLED,,}" in
        true | false | 1 | 0 | yes | no | on | off) ;;
        *)
            log ERROR "Некорректный SELF_CHECK_ENABLED: ${SELF_CHECK_ENABLED}"
            return 1
            ;;
    esac
    if [[ ! "${SELF_CHECK_TIMEOUT_SEC:-}" =~ ^[0-9]+$ ]] || ((SELF_CHECK_TIMEOUT_SEC < 2 || SELF_CHECK_TIMEOUT_SEC > 60)); then
        log ERROR "Некорректный SELF_CHECK_TIMEOUT_SEC: ${SELF_CHECK_TIMEOUT_SEC} (ожидается 2-60)"
        return 1
    fi
    local self_check_url
    while read -r self_check_url; do
        self_check_url=$(trim_ws "$self_check_url")
        [[ -z "$self_check_url" ]] && continue
        if ! is_valid_https_url "$self_check_url"; then
            log ERROR "SELF_CHECK_URLS содержит невалидный HTTPS URL: ${self_check_url}"
            return 1
        fi
    done < <(split_list "$SELF_CHECK_URLS")

    local port
    while read -r port; do
        port=$(trim_ws "$port")
        [[ -z "$port" ]] && continue
        if ! is_valid_port "$port"; then
            log ERROR "REALITY_TEST_PORTS содержит невалидный порт: ${port}"
            return 1
        fi
    done < <(split_list "$REALITY_TEST_PORTS")
}

strict_validate_runtime_profile_inputs() {
    if [[ -n "$XRAY_VERSION" ]]; then
        if [[ "${XRAY_VERSION,,}" != "latest" ]]; then
            if [[ ! "$XRAY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
                log ERROR "Некорректный XRAY_VERSION: ${XRAY_VERSION}"
                return 1
            fi
        fi
    fi
    if [[ -n "$XRAY_CLIENT_MIN_VERSION" ]] && ! [[ "$XRAY_CLIENT_MIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
        log ERROR "Некорректный XRAY_CLIENT_MIN_VERSION: ${XRAY_CLIENT_MIN_VERSION}"
        return 1
    fi
    if [[ -n "${XRAY_DOMAIN_PROFILE:-}" ]] && ! normalize_domain_tier "$XRAY_DOMAIN_PROFILE" > /dev/null 2>&1; then
        log ERROR "Некорректный XRAY_DOMAIN_PROFILE: ${XRAY_DOMAIN_PROFILE} (ожидается ru|ru-auto|global-50|global-50-auto|custom)"
        return 1
    fi
    if [[ -n "${XRAY_DOMAIN_TIER:-}" ]] && ! normalize_domain_tier "$XRAY_DOMAIN_TIER" > /dev/null 2>&1; then
        log ERROR "Некорректный XRAY_DOMAIN_TIER: ${XRAY_DOMAIN_TIER}"
        return 1
    fi
    strict_validate_primary_domain_controls || return 1
}

strict_validate_runtime_custom_domain_inputs() {
    if [[ -n "$XRAY_CUSTOM_DOMAINS" ]]; then
        local domain
        while read -r domain; do
            domain=$(trim_ws "$domain")
            [[ -z "$domain" ]] && continue
            if ! is_valid_domain "$domain"; then
                log ERROR "XRAY_CUSTOM_DOMAINS содержит невалидный домен: ${domain}"
                return 1
            fi
        done < <(load_domain_list "$XRAY_CUSTOM_DOMAINS")
    fi
    if [[ -z "$XRAY_CUSTOM_DOMAINS" && -n "$XRAY_DOMAINS_FILE" ]]; then
        if [[ ! -f "$XRAY_DOMAINS_FILE" ]]; then
            log ERROR "XRAY_DOMAINS_FILE не найден: ${XRAY_DOMAINS_FILE}"
            return 1
        fi
        local file_domain
        local file_domains_count=0
        while read -r file_domain; do
            file_domain=$(trim_ws "$file_domain")
            [[ -z "$file_domain" ]] && continue
            if ! is_valid_domain "$file_domain"; then
                log ERROR "XRAY_DOMAINS_FILE содержит невалидный домен: ${file_domain}"
                return 1
            fi
            file_domains_count=$((file_domains_count + 1))
        done < <(load_domains_from_file "$XRAY_DOMAINS_FILE")
        if ((file_domains_count < 1)); then
            log ERROR "XRAY_DOMAINS_FILE не содержит валидных доменов: ${XRAY_DOMAINS_FILE}"
            return 1
        fi
    fi
}

strict_validate_runtime_action_contracts() {
    local action="${1:-$ACTION}"
    case "$action" in
        install | add-clients | add-keys)
            validate_install_config || return 1
            local effective_domain_source_tier="${DOMAIN_TIER:-}"
            local normalized_effective_domain_source_tier=""
            if [[ -z "$effective_domain_source_tier" && -n "${DOMAIN_PROFILE:-}" ]]; then
                effective_domain_source_tier="$DOMAIN_PROFILE"
            fi
            if [[ -z "$effective_domain_source_tier" && -n "${XRAY_DOMAIN_PROFILE:-}" ]]; then
                effective_domain_source_tier="$XRAY_DOMAIN_PROFILE"
            fi
            if [[ -z "$effective_domain_source_tier" && -n "${XRAY_DOMAIN_TIER:-}" ]]; then
                effective_domain_source_tier="$XRAY_DOMAIN_TIER"
            fi
            normalized_effective_domain_source_tier="$(normalize_domain_tier "${effective_domain_source_tier:-tier_ru}" 2> /dev/null || echo "")"
            if [[ -z "$XRAY_CUSTOM_DOMAINS" && -z "$XRAY_DOMAINS_FILE" && "$normalized_effective_domain_source_tier" == "custom" ]]; then
                log ERROR "Custom-профиль требует managed source доменов: восстановите ${XRAY_MANAGED_CUSTOM_DOMAINS_FILE} или повторно задайте XRAY_CUSTOM_DOMAINS/XRAY_DOMAINS_FILE."
                return 1
            fi
            ;;
        *) ;;
    esac

    return 0
}

strict_validate_runtime_inputs() {
    local action="${1:-$ACTION}"

    strict_validate_runtime_safe_vars || return 1
    strict_validate_runtime_action_paths "$action" || return 1
    strict_validate_runtime_file_contracts || return 1
    strict_validate_runtime_download_contracts || return 1
    strict_validate_runtime_network_identity || return 1
    strict_validate_runtime_probe_settings || return 1
    strict_validate_runtime_profile_inputs || return 1
    strict_validate_runtime_custom_domain_inputs || return 1
    strict_validate_runtime_action_contracts "$action" || return 1

    return 0
}

validate_install_config() {
    local normalized_tier
    if ! normalized_tier=$(normalize_domain_tier "$DOMAIN_TIER"); then
        log WARN "Неверный DOMAIN_TIER: $DOMAIN_TIER — используем tier_ru"
        normalized_tier="tier_ru"
    fi
    DOMAIN_TIER="$normalized_tier"
    transport_normalize_assign TRANSPORT "$TRANSPORT"
    case "$TRANSPORT" in
        xhttp) ;;
        grpc | http2)
            log ERROR "TRANSPORT=${TRANSPORT} больше не поддерживается в v7; используйте xhttp или migrate-stealth для legacy install"
            return 1
            ;;
        *)
            log ERROR "Неверный TRANSPORT: $TRANSPORT (в v7 поддерживается только xhttp)"
            return 1
            ;;
    esac
    local max_configs
    max_configs=$(max_configs_for_tier "$DOMAIN_TIER")
    if [[ ! "$NUM_CONFIGS" =~ ^[0-9]+$ ]] || ((NUM_CONFIGS < 1 || NUM_CONFIGS > max_configs)); then
        log ERROR "Некорректное количество конфигураций: ${NUM_CONFIGS} (лимит для ${DOMAIN_TIER}: 1-${max_configs})"
        return 1
    fi
    if [[ ! "$START_PORT" =~ ^[0-9]+$ ]] || [[ $START_PORT -lt 1 ]] || [[ $START_PORT -gt 65535 ]]; then
        log ERROR "Некорректный порт: $START_PORT"
        return 1
    fi
    case "$MUX_MODE" in
        on | off | auto) ;;
        *)
            log WARN "Неверный MUX_MODE: $MUX_MODE (используем off)"
            MUX_MODE="off"
            ;;
    esac
    if transport_is_xhttp "$TRANSPORT" && [[ "$MUX_MODE" != "off" ]]; then
        log WARN "MUX не используется в xhttp-first режиме; принудительно отключаем"
        MUX_MODE="off"
    fi
    if [[ ! "$MUX_CONCURRENCY_MIN" =~ ^[0-9]+$ ]] || [[ ! "$MUX_CONCURRENCY_MAX" =~ ^[0-9]+$ ]]; then
        log ERROR "Некорректные значения MUX_CONCURRENCY"
        return 1
    fi
    if [[ $MUX_CONCURRENCY_MIN -gt $MUX_CONCURRENCY_MAX ]]; then
        local tmp="$MUX_CONCURRENCY_MIN"
        MUX_CONCURRENCY_MIN="$MUX_CONCURRENCY_MAX"
        MUX_CONCURRENCY_MAX="$tmp"
    fi
    if [[ ! "$SHORT_ID_BYTES_MIN" =~ ^[0-9]+$ ]] || [[ ! "$SHORT_ID_BYTES_MAX" =~ ^[0-9]+$ ]]; then
        log ERROR "Некорректные SHORT_ID_BYTES_MIN/MAX"
        return 1
    fi
    if ((SHORT_ID_BYTES_MIN < 8)); then
        log WARN "SHORT_ID_BYTES_MIN < 8 небезопасно, используем 8"
        SHORT_ID_BYTES_MIN=8
    fi
    if ((SHORT_ID_BYTES_MAX > 32)); then
        log WARN "SHORT_ID_BYTES_MAX > 32 не поддерживается, используем 32"
        SHORT_ID_BYTES_MAX=32
    fi
    if ((SHORT_ID_BYTES_MIN > SHORT_ID_BYTES_MAX)); then
        local sid_tmp="$SHORT_ID_BYTES_MIN"
        SHORT_ID_BYTES_MIN="$SHORT_ID_BYTES_MAX"
        SHORT_ID_BYTES_MAX="$sid_tmp"
    fi
    return 0
}
detect_current_managed_transport() {
    if [[ -f "$XRAY_CONFIG" ]] && command -v jq > /dev/null 2>&1; then
        local transport_mode
        transport_mode=$(jq -r '
            .inbounds[]
            | select(.streamSettings.realitySettings != null)
            | select((.listen // "0.0.0.0") | test(":") | not)
            | .streamSettings.network // "xhttp"
        ' "$XRAY_CONFIG" 2> /dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')
        transport_normalize_assign transport_mode "$transport_mode"
        case "$transport_mode" in
            grpc | http2 | xhttp) printf '%s\n' "$transport_mode" ;;
            "") printf '%s\n' "$(transport_normalize "${TRANSPORT:-xhttp}")" ;;
            *) printf '%s\n' "unknown" ;;
        esac
        return 0
    fi
    printf '%s\n' "$(transport_normalize "${TRANSPORT:-xhttp}")"
}
