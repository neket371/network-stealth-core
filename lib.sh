#!/usr/bin/env bash
# Network Stealth Core 7.3.8 - Автоматизация strongest-direct Xray Reality (policy, schema v3, canary, adaptive repair)

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

readonly SCRIPT_VERSION="7.3.8"
readonly SCRIPT_NAME="Network Stealth Core"

XRAY_USER="xray"
XRAY_GROUP="xray"
XRAY_HOME="${XRAY_HOME:-/var/lib/xray}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_GEO_DIR="${XRAY_GEO_DIR:-}"
XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/config.json}"
XRAY_ENV="${XRAY_ENV:-/etc/xray-reality/config.env}"
XRAY_POLICY="${XRAY_POLICY:-/etc/xray-reality/policy.json}"
XRAY_MANAGED_CUSTOM_DOMAINS_FILE="${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:-/etc/xray-reality/custom-domains.txt}"
XRAY_KEYS="${XRAY_KEYS:-/etc/xray/private/keys}"
XRAY_BACKUP="${XRAY_BACKUP:-/var/backups/xray}"
XRAY_LOGS="${XRAY_LOGS:-/var/log/xray}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/xray-install.log}"
LOG_CONTEXT="${LOG_CONTEXT:-установки}"
MINISIGN_KEY="${MINISIGN_KEY:-/etc/xray/minisign.pub}"

MAX_BACKUPS="${MAX_BACKUPS:-10}"
CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-10}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-60}"
DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"
DOWNLOAD_RETRY_DELAY="${DOWNLOAD_RETRY_DELAY:-2}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-120}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-10}"
KEEP_LOCAL_BACKUPS="${KEEP_LOCAL_BACKUPS:-true}"
XRAY_TRANSPORT="${XRAY_TRANSPORT:-}"
XRAY_ADVANCED="${XRAY_ADVANCED:-}"
TRANSPORT="${TRANSPORT:-xhttp}" # xhttp only (legacy grpc/http2 require migrate-stealth)
MUX_MODE="${MUX_MODE:-off}"     # off by default for xhttp-first installs
MUX_CONCURRENCY_MIN="${MUX_CONCURRENCY_MIN:-3}"
MUX_CONCURRENCY_MAX="${MUX_CONCURRENCY_MAX:-20}"
GRPC_IDLE_TIMEOUT_MIN="${GRPC_IDLE_TIMEOUT_MIN:-60}"
GRPC_IDLE_TIMEOUT_MAX="${GRPC_IDLE_TIMEOUT_MAX:-1800}"
GRPC_HEALTH_TIMEOUT_MIN="${GRPC_HEALTH_TIMEOUT_MIN:-10}"
GRPC_HEALTH_TIMEOUT_MAX="${GRPC_HEALTH_TIMEOUT_MAX:-30}"
TCP_KEEPALIVE_MIN="${TCP_KEEPALIVE_MIN:-20}"
TCP_KEEPALIVE_MAX="${TCP_KEEPALIVE_MAX:-45}"
SHORT_ID_BYTES_MIN="${SHORT_ID_BYTES_MIN:-8}"
SHORT_ID_BYTES_MAX="${SHORT_ID_BYTES_MAX:-8}"
REUSE_EXISTING="${REUSE_EXISTING:-true}"
AUTO_ROLLBACK="${AUTO_ROLLBACK:-true}"
XRAY_VERSION="${XRAY_VERSION:-}"
XRAY_MIRRORS="${XRAY_MIRRORS:-}"
MINISIGN_MIRRORS="${MINISIGN_MIRRORS:-}"
QR_ENABLED="${QR_ENABLED:-auto}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
AUTO_UPDATE_ONCALENDAR="${AUTO_UPDATE_ONCALENDAR:-weekly}"
AUTO_UPDATE_RANDOM_DELAY="${AUTO_UPDATE_RANDOM_DELAY:-1h}"
ALLOW_INSECURE_SHA256="${ALLOW_INSECURE_SHA256:-false}"
ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP="${ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP:-false}"
REQUIRE_MINISIGN="${REQUIRE_MINISIGN:-false}"
ALLOW_NO_SYSTEMD="${ALLOW_NO_SYSTEMD:-false}"
XRAY_SCRIPT_PATH="${XRAY_SCRIPT_PATH:-/usr/local/bin/xray-reality.sh}"
XRAY_UPDATE_SCRIPT="${XRAY_UPDATE_SCRIPT:-/usr/local/bin/xray-reality-update.sh}"
UPDATE_LOG="${UPDATE_LOG:-/var/log/xray-update.log}"
DIAG_LOG="${DIAG_LOG:-/var/log/xray-diagnose.log}"
HEALTH_LOG="${HEALTH_LOG:-}"
XRAY_GEOIP_URL="${XRAY_GEOIP_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat}"
XRAY_GEOSITE_URL="${XRAY_GEOSITE_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat}"
XRAY_GEOIP_SHA256_URL="${XRAY_GEOIP_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum}"
XRAY_GEOSITE_SHA256_URL="${XRAY_GEOSITE_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum}"
GEO_VERIFY_HASH="${GEO_VERIFY_HASH:-true}"
GEO_VERIFY_STRICT="${GEO_VERIFY_STRICT:-false}"
XRAY_CONFIG_FILE="${XRAY_CONFIG_FILE:-}"
XRAY_CUSTOM_DOMAINS="${XRAY_CUSTOM_DOMAINS:-}"
XRAY_DOMAINS_FILE="${XRAY_DOMAINS_FILE:-}"
XRAY_DATA_DIR="${XRAY_DATA_DIR:-}"
XRAY_TIERS_FILE="${XRAY_TIERS_FILE:-}"
XRAY_SNI_POOLS_FILE="${XRAY_SNI_POOLS_FILE:-}"
XRAY_TRANSPORT_ENDPOINTS_FILE="${XRAY_TRANSPORT_ENDPOINTS_FILE:-}"
XRAY_GRPC_SERVICES_FILE="${XRAY_GRPC_SERVICES_FILE:-}"
XRAY_DOMAIN_CATALOG_FILE="${XRAY_DOMAIN_CATALOG_FILE:-}"
XRAY_DOMAIN_TIER="${XRAY_DOMAIN_TIER:-}"
XRAY_DOMAIN_PROFILE="${XRAY_DOMAIN_PROFILE:-}"
XRAY_NUM_CONFIGS="${XRAY_NUM_CONFIGS:-}"
XRAY_SPIDER_MODE="${XRAY_SPIDER_MODE:-}"
XRAY_START_PORT="${XRAY_START_PORT:-}"
XRAY_PROGRESS_MODE="${XRAY_PROGRESS_MODE:-}"
DOMAIN_TIER="${DOMAIN_TIER:-tier_ru}"
NUM_CONFIGS="${NUM_CONFIGS:-5}"
SPIDER_MODE="${SPIDER_MODE:-true}"
START_PORT="${START_PORT:-443}"
PROGRESS_MODE="${PROGRESS_MODE:-${XRAY_PROGRESS_MODE:-auto}}" # auto|bar|plain|none
DOMAIN_CHECK="${DOMAIN_CHECK:-true}"
DOMAIN_CHECK_TIMEOUT="${DOMAIN_CHECK_TIMEOUT:-3}"
DOMAIN_CHECK_PARALLELISM="${DOMAIN_CHECK_PARALLELISM:-16}"
REALITY_TEST_PORTS="${REALITY_TEST_PORTS:-443,8443}"
SKIP_REALITY_CHECK="${SKIP_REALITY_CHECK:-false}"
DOMAIN_HEALTH_FILE="${DOMAIN_HEALTH_FILE:-/var/lib/xray/domain-health.json}"
DOMAIN_HEALTH_PROBE_TIMEOUT="${DOMAIN_HEALTH_PROBE_TIMEOUT:-2}"
DOMAIN_HEALTH_RANKING="${DOMAIN_HEALTH_RANKING:-true}"
DOMAIN_HEALTH_RATE_LIMIT_MS="${DOMAIN_HEALTH_RATE_LIMIT_MS:-250}"
DOMAIN_HEALTH_MAX_PROBES="${DOMAIN_HEALTH_MAX_PROBES:-20}"
DOMAIN_QUARANTINE_FAIL_STREAK="${DOMAIN_QUARANTINE_FAIL_STREAK:-4}"
DOMAIN_QUARANTINE_COOLDOWN_MIN="${DOMAIN_QUARANTINE_COOLDOWN_MIN:-120}"
PRIMARY_DOMAIN_MODE="${PRIMARY_DOMAIN_MODE:-adaptive}"
PRIMARY_PIN_DOMAIN="${PRIMARY_PIN_DOMAIN:-}"
PRIMARY_ADAPTIVE_TOP_N="${PRIMARY_ADAPTIVE_TOP_N:-5}"
MEASUREMENTS_DIR="${MEASUREMENTS_DIR:-/var/lib/xray/measurements}"
MEASUREMENTS_SUMMARY_FILE="${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
SELF_CHECK_HISTORY_FILE="${SELF_CHECK_HISTORY_FILE:-/var/lib/xray/self-check-history.ndjson}"
STEALTH_CONTRACT_VERSION="${STEALTH_CONTRACT_VERSION:-7.3.8}"
XRAY_CLIENT_MIN_VERSION="${XRAY_CLIENT_MIN_VERSION:-25.9.5}"
XRAY_DIRECT_FLOW="${XRAY_DIRECT_FLOW:-xtls-rprx-vision}"
BROWSER_DIALER_ENV_NAME="${BROWSER_DIALER_ENV_NAME:-xray.browser.dialer}"
XRAY_BROWSER_DIALER_ADDRESS="${XRAY_BROWSER_DIALER_ADDRESS:-}"
DOWNLOAD_HOST_ALLOWLIST="${DOWNLOAD_HOST_ALLOWLIST:-github.com,api.github.com,objects.githubusercontent.com,raw.githubusercontent.com,release-assets.githubusercontent.com,ghproxy.com}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://ghproxy.com/https://github.com}"
ACTION="install"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
AUTO_PROFILE_MODE="${AUTO_PROFILE_MODE:-false}"
REPLAN="${REPLAN:-false}"
ROLLBACK_DIR=""
SYSTEMD_MANAGEMENT_DISABLED="${SYSTEMD_MANAGEMENT_DISABLED:-false}"
SERVER_IP="${SERVER_IP:-}"
SERVER_IP6="${SERVER_IP6:-}"
SKIP_MINISIGN=false
MUX_ENABLED=false
MUX_CONCURRENCY=0
HAS_IPV6=false
PORTS=()
PORTS_V6=()
PRIVATE_KEYS=()
PUBLIC_KEYS=()
UUIDS=()
SHORT_IDS=()
CONFIG_DOMAINS=()
CONFIG_SNIS=()
CONFIG_TRANSPORT_ENDPOINTS=()
CONFIG_DESTS=()
CONFIG_FPS=()
CONFIG_PROVIDER_FAMILIES=()
CONFIG_VLESS_ENCRYPTIONS=()
CONFIG_VLESS_DECRYPTIONS=()
AVAILABLE_DOMAINS=()
declare -A DOMAIN_PROVIDER_FAMILIES=()
declare -A DOMAIN_REGIONS=()
declare -A DOMAIN_PRIORITY_MAP=()
declare -A DOMAIN_RISK_MAP=()
declare -A DOMAIN_PORT_HINTS=()
declare -A DOMAIN_SNI_POOL_OVERRIDES=()
REUSE_EXISTING_CONFIG=false
# shellcheck disable=SC2034 # Used by logs/add-clients handlers in sourced modules.
LOGS_TARGET=""
# shellcheck disable=SC2034 # Used by add-clients/add-keys handlers in sourced modules.
ADD_CLIENTS_COUNT=""
LOGGING_BACKEND="none"
LOGGING_STDOUT_FD=""
LOGGING_STDERR_FD=""
LOGGING_FIFO=""
LOGGING_TEE_PID=""
PROGRESS_LINE_OPEN=false
PROGRESS_LAST_PERCENT=-1
PROGRESS_RENDER_MODE=""
PROGRESS_RENDER_MODE_SOURCE=""
PROGRESS_MODE_WARNED=false
: "${LOGGING_BACKEND}" "${LOGGING_STDOUT_FD}" "${LOGGING_STDERR_FD}" "${LOGGING_FIFO}" "${LOGGING_TEE_PID}"
: "${PROGRESS_LINE_OPEN}" "${PROGRESS_LAST_PERCENT}" "${PROGRESS_RENDER_MODE}" "${PROGRESS_RENDER_MODE_SOURCE}" "${PROGRESS_MODE_WARNED}"
FIREWALL_ROLLBACK_ENTRIES=()
FIREWALL_FIREWALLD_DIRTY=false
CREATED_PATHS=()
declare -A CREATED_PATH_SET=()

: "${XRAY_USER}" "${XRAY_GROUP}" "${XRAY_HOME}" "${XRAY_LOGS}" "${MINISIGN_KEY}"
: "${SKIP_MINISIGN}" "${MUX_ENABLED}" "${MUX_CONCURRENCY}"
: "${HAS_IPV6}"
: "${HEALTH_LOG}"
: "${PORTS[@]}" "${PORTS_V6[@]}"
: "${PRIVATE_KEYS[@]}" "${PUBLIC_KEYS[@]}" "${UUIDS[@]}" "${SHORT_IDS[@]}"
: "${CONFIG_DOMAINS[@]}" "${CONFIG_SNIS[@]}" "${CONFIG_TRANSPORT_ENDPOINTS[@]}" "${CONFIG_DESTS[@]}" "${CONFIG_FPS[@]}" "${CONFIG_PROVIDER_FAMILIES[@]}" "${CONFIG_VLESS_ENCRYPTIONS[@]}" "${CONFIG_VLESS_DECRYPTIONS[@]}" "${AVAILABLE_DOMAINS[@]}"

sync_transport_endpoint_file_contract() {
    local default_path="${XRAY_DATA_DIR:-/usr/local/share/xray-reality}/transport_endpoints.map"
    local legacy_default_path="${XRAY_DATA_DIR:-/usr/local/share/xray-reality}/grpc_services.map"

    if [[ -z "${XRAY_TRANSPORT_ENDPOINTS_FILE:-}" ]]; then
        if [[ -n "${XRAY_GRPC_SERVICES_FILE:-}" ]]; then
            XRAY_TRANSPORT_ENDPOINTS_FILE="$XRAY_GRPC_SERVICES_FILE"
        elif [[ -f "$default_path" || ! -f "$legacy_default_path" ]]; then
            XRAY_TRANSPORT_ENDPOINTS_FILE="$default_path"
        else
            XRAY_TRANSPORT_ENDPOINTS_FILE="$legacy_default_path"
        fi
    fi

    if [[ -z "${XRAY_GRPC_SERVICES_FILE:-}" ]]; then
        XRAY_GRPC_SERVICES_FILE="$XRAY_TRANSPORT_ENDPOINTS_FILE"
    fi
}

DEFAULT_DATA_DIR="/usr/local/share/xray-reality"
if [[ -z "${XRAY_DATA_DIR:-}" ]]; then
    XRAY_DATA_DIR="$DEFAULT_DATA_DIR"
fi
export XRAY_DATA_DIR
XRAY_TIERS_FILE="${XRAY_TIERS_FILE:-$XRAY_DATA_DIR/domains.tiers}"
XRAY_SNI_POOLS_FILE="${XRAY_SNI_POOLS_FILE:-$XRAY_DATA_DIR/sni_pools.map}"
XRAY_TRANSPORT_ENDPOINTS_FILE="${XRAY_TRANSPORT_ENDPOINTS_FILE:-$XRAY_DATA_DIR/transport_endpoints.map}"
sync_transport_endpoint_file_contract
XRAY_DOMAIN_CATALOG_FILE="${XRAY_DOMAIN_CATALOG_FILE:-$XRAY_DATA_DIR/data/domains/catalog.json}"

MODULE_DIR="$SCRIPT_DIR"
if [[ ! -f "$MODULE_DIR/install.sh" || ! -f "$MODULE_DIR/config.sh" ]]; then
    if [[ -f "$XRAY_DATA_DIR/install.sh" && -f "$XRAY_DATA_DIR/config.sh" ]]; then
        MODULE_DIR="$XRAY_DATA_DIR"
    fi
fi

LIB_COMMON_UTILS_MODULE="$MODULE_DIR/modules/lib/common_utils.sh"
if [[ ! -f "$LIB_COMMON_UTILS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_COMMON_UTILS_MODULE="$XRAY_DATA_DIR/modules/lib/common_utils.sh"
fi
if [[ ! -f "$LIB_COMMON_UTILS_MODULE" ]]; then
    echo "ERROR: не найден модуль общих утилит: $LIB_COMMON_UTILS_MODULE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_COMMON_UTILS_MODULE"

LIB_TTY_MODULE="$MODULE_DIR/modules/lib/tty.sh"
if [[ ! -f "$LIB_TTY_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_TTY_MODULE="$XRAY_DATA_DIR/modules/lib/tty.sh"
fi
if [[ ! -f "$LIB_TTY_MODULE" ]]; then
    echo "ERROR: не найден модуль tty helper'ов: $LIB_TTY_MODULE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_TTY_MODULE"

_try_dir() {
    local dir="$1"
    if [[ -d "$dir" && -w "$dir" ]]; then
        return 0
    fi
    mkdir -p "$dir" 2> /dev/null && [[ -w "$dir" ]]
}

_try_file_path() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    _try_dir "$dir"
}

_stat_brief() {
    local path="$1"
    if command -v stat > /dev/null 2>&1; then
        stat -c '%A %U:%G' "$path" 2> /dev/null && return 0
        stat -f '%Sp %Su:%Sg' "$path" 2> /dev/null && return 0
    fi
    echo "не существует"
}

_resolve_path() {
    local var_name="$1"
    local description="$2"
    local primary="$3"
    local fallback="$4"

    if _try_file_path "$primary" || _try_dir "$primary"; then
        printf -v "$var_name" '%s' "$primary"
        return 0
    fi

    log WARN "${description}: ${primary} недоступен, пробуем ${fallback}..."
    if _try_file_path "$fallback" || _try_dir "$fallback"; then
        printf -v "$var_name" '%s' "$fallback"
        log OK "${description}: используем ${fallback}"
        return 0
    fi

    log ERROR "${description}: не удалось найти подходящий путь"
    echo ""
    echo -e "  Попробованные пути:"
    echo -e "    ${primary} — $(_stat_brief "$(dirname "$primary")")"
    echo -e "    ${fallback} — $(_stat_brief "$(dirname "$fallback")")"
    echo ""

    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        log ERROR "Non-interactive режим: нет возможности запросить путь вручную"
        return 1
    fi

    local custom_path tty_read_fd tty_write_fd
    if ! open_interactive_tty_fds tty_read_fd tty_write_fd; then
        log ERROR "Терминал /dev/tty недоступен: невозможно запросить путь вручную"
        return 1
    fi
    while true; do
        if ! tty_printf "$tty_write_fd" '  Укажите путь вручную для %s: ' "$description"; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось вывести приглашение ввода пути в /dev/tty"
            return 1
        fi
        if ! read -r -u "$tty_read_fd" custom_path; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось прочитать путь из /dev/tty"
            return 1
        fi
        custom_path=$(normalize_tty_input "$custom_path")
        if [[ -z "$custom_path" ]]; then
            tty_printf "$tty_write_fd" '  %bПуть не может быть пустым%b\n' "$RED" "$NC"
            continue
        fi
        if _try_file_path "$custom_path" || _try_dir "$custom_path"; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            printf -v "$var_name" '%s' "$custom_path"
            log OK "${description}: используем ${custom_path}"
            return 0
        fi
        tty_printf "$tty_write_fd" '  %bПуть %s недоступен для записи%b\n' "$RED" "$custom_path" "$NC"
    done
}

resolve_paths() {
    log STEP "Проверяем системные пути..."
    local resolve_errors=0

    if ! _resolve_path XRAY_BIN "Бинарник Xray" \
        "/usr/local/bin/xray" "/opt/xray/bin/xray"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if [[ -z "${XRAY_GEO_DIR:-}" ]]; then
        XRAY_GEO_DIR="$(dirname "$XRAY_BIN")"
    fi
    if ! _resolve_path XRAY_GEO_DIR "Geo-ресурсы Xray" \
        "$XRAY_GEO_DIR" "/usr/local/share/xray"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_CONFIG "Конфигурация" \
        "/etc/xray/config.json" "/opt/xray/etc/config.json"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    local config_dir
    config_dir=$(dirname "$XRAY_CONFIG")
    if ! _resolve_path XRAY_KEYS "Ключи клиентов" \
        "${config_dir}/private/keys" "/opt/xray/etc/private/keys"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path MINISIGN_KEY "Ключ Minisign" \
        "${config_dir}/minisign.pub" "/opt/xray/etc/minisign.pub"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_ENV "Файл окружения" \
        "/etc/xray-reality/config.env" "/opt/xray/etc/config.env"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_POLICY "Файл policy" \
        "/etc/xray-reality/policy.json" "/opt/xray/etc/policy.json"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_LOGS "Директория логов" \
        "/var/log/xray" "/opt/xray/log"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    local logs_parent
    logs_parent=$(dirname "$XRAY_LOGS")
    INSTALL_LOG="${logs_parent}/xray-install.log"
    if [[ -z "${HEALTH_LOG:-}" ]]; then
        HEALTH_LOG="${XRAY_LOGS%/}/xray-health.log"
    fi
    if ! _resolve_path XRAY_HOME "Домашняя директория" \
        "/var/lib/xray" "/opt/xray/data"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path MEASUREMENTS_DIR "Директория measurements" \
        "/var/lib/xray/measurements" "/opt/xray/data/measurements"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_BACKUP "Директория бэкапов" \
        "/var/backups/xray" "/opt/xray/backups"; then
        resolve_errors=$((resolve_errors + 1))
    fi
    if ! _resolve_path XRAY_DATA_DIR "Данные скрипта" \
        "/usr/local/share/xray-reality" "/opt/xray/share"; then
        resolve_errors=$((resolve_errors + 1))
    fi

    XRAY_TIERS_FILE="$XRAY_DATA_DIR/domains.tiers"
    XRAY_SNI_POOLS_FILE="$XRAY_DATA_DIR/sni_pools.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE="$XRAY_DATA_DIR/transport_endpoints.map"
    sync_transport_endpoint_file_contract
    XRAY_DOMAIN_CATALOG_FILE="$XRAY_DATA_DIR/data/domains/catalog.json"
    SELF_CHECK_HISTORY_FILE="${XRAY_HOME%/}/self-check-history.ndjson"
    MEASUREMENTS_SUMMARY_FILE="${MEASUREMENTS_DIR%/}/latest-summary.json"

    local bin_dir
    bin_dir=$(dirname "$XRAY_BIN")
    XRAY_SCRIPT_PATH="${bin_dir}/xray-reality.sh"
    XRAY_UPDATE_SCRIPT="${bin_dir}/xray-reality-update.sh"

    if ((resolve_errors > 0)); then
        log ERROR "Проверка системных путей завершилась с ошибками (${resolve_errors})"
        return 1
    fi

    log OK "Все пути проверены"
}

LIB_UI_LOGGING_MODULE="$MODULE_DIR/modules/lib/ui_logging.sh"
if [[ ! -f "$LIB_UI_LOGGING_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_UI_LOGGING_MODULE="$XRAY_DATA_DIR/modules/lib/ui_logging.sh"
fi
if [[ ! -f "$LIB_UI_LOGGING_MODULE" ]]; then
    echo "ERROR: не найден модуль ui/logging: $LIB_UI_LOGGING_MODULE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_UI_LOGGING_MODULE"

LIB_SYSTEM_RUNTIME_MODULE="$MODULE_DIR/modules/lib/system_runtime.sh"
if [[ ! -f "$LIB_SYSTEM_RUNTIME_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_SYSTEM_RUNTIME_MODULE="$XRAY_DATA_DIR/modules/lib/system_runtime.sh"
fi
if [[ ! -f "$LIB_SYSTEM_RUNTIME_MODULE" ]]; then
    log ERROR "Не найден модуль system runtime: $LIB_SYSTEM_RUNTIME_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_SYSTEM_RUNTIME_MODULE"

LIB_DOWNLOADS_MODULE="$MODULE_DIR/modules/lib/downloads.sh"
if [[ ! -f "$LIB_DOWNLOADS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_DOWNLOADS_MODULE="$XRAY_DATA_DIR/modules/lib/downloads.sh"
fi
if [[ ! -f "$LIB_DOWNLOADS_MODULE" ]]; then
    log ERROR "Не найден модуль downloads: $LIB_DOWNLOADS_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_DOWNLOADS_MODULE"

fetch_ip() {
    local family="$1"
    local curl_flag="-s"
    if [[ "$family" == "4" || "$family" == "6" ]]; then
        curl_flag="-s${family}"
    fi
    local -a endpoints=(
        "https://ifconfig.me"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
    )
    local url ip
    for url in "${endpoints[@]}"; do
        ip=$(curl_fetch_text "$url" "$curl_flag" --connect-timeout "$CONNECTION_TIMEOUT" --max-time 5 2> /dev/null || true)
        ip=$(trim_ws "$ip")
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

atomic_write() {
    local target="$1"
    local mode="${2:-}"
    local target_existed=false
    if [[ -e "$target" ]]; then
        target_existed=true
    fi

    local resolved
    resolved=$(realpath -m "$target" 2> /dev/null) || {
        log ERROR "atomic_write: не удалось разрешить путь: $target"
        return 1
    }

    if [[ "$resolved" == *".."* ]] || [[ "$target" == *".."* ]]; then
        log ERROR "atomic_write: путь содержит ..: $target"
        return 1
    fi

    local -a safe_prefixes=(
        "/etc/xray" "/etc/systemd" "/usr/lib/systemd" "/lib/systemd" "/var/log" "/var/backups/xray"
        "/usr/local" "/var/lib/xray" "/etc/logrotate.d"
        "/etc/xray-reality" "/etc/sysctl.d" "/etc/security"
        "/opt/xray"
    )
    local is_safe=false
    for prefix in "${safe_prefixes[@]}"; do
        if [[ "$resolved" == "$prefix" || "$resolved" == "$prefix"/* ]]; then
            is_safe=true
            break
        fi
    done

    if [[ "$is_safe" != true ]]; then
        log ERROR "atomic_write: путь вне разрешённых директорий: $target"
        return 1
    fi

    local dir
    dir=$(dirname "$target")
    mkdir -p "$dir"
    local tmp
    local _old_umask
    _old_umask=$(umask)
    umask 077
    tmp=$(mktemp "${target}.tmp.XXXXXX")
    umask "$_old_umask"
    cat > "$tmp"
    if [[ -n "$mode" ]]; then
        chmod "$mode" "$tmp"
    fi
    mv "$tmp" "$target"
    if [[ "$target_existed" != true ]]; then
        record_created_path "$target"
    fi
}

RAND_U32_VALUE=0
RAND_U32_MAX=32767

rand_u32() {
    if [[ -r /dev/urandom ]] && command -v od > /dev/null 2>&1; then
        local n
        n=$(od -An -N4 -tu4 /dev/urandom 2> /dev/null | tr -d '[:space:]')
        if [[ "$n" =~ ^[0-9]+$ ]]; then
            RAND_U32_VALUE="$n"
            RAND_U32_MAX=4294967295
            echo "$n"
            return 0
        fi
    fi
    if command -v openssl > /dev/null 2>&1; then
        local hex
        hex=$(openssl rand -hex 4 2> /dev/null || true)
        if [[ "$hex" =~ ^[0-9a-fA-F]{8}$ ]]; then
            RAND_U32_VALUE="$((16#$hex))"
            RAND_U32_MAX=4294967295
            echo "$RAND_U32_VALUE"
            return 0
        fi
    fi
    RAND_U32_VALUE="$RANDOM"
    RAND_U32_MAX=32767
    echo "$RAND_U32_VALUE"
}

rand_between() {
    local min="$1"
    local max="$2"
    if [[ "$max" -lt "$min" ]]; then
        echo "$min"
        return
    fi
    local span=$((max - min + 1))
    if ((span <= 1)); then
        echo "$min"
        return
    fi

    local source_max rnd bucket_limit
    while true; do
        rand_u32 > /dev/null
        rnd="$RAND_U32_VALUE"
        source_max="$RAND_U32_MAX"

        if ((source_max < span)); then
            echo "$((rnd % span + min))"
            return
        fi

        bucket_limit=$((((source_max + 1) / span) * span))
        if ((rnd < bucket_limit)); then
            echo "$((rnd % span + min))"
            return
        fi
    done
}

normalize_domain_tier() {
    local raw="${1:-}"
    local value="${raw,,}"
    value="${value// /}"
    value="${value//_/-}"
    case "$value" in
        "" | ru | russia | rf | tier-ru | ru-auto | russia-auto | rf-auto | tier-ru-auto)
            echo "tier_ru"
            return 0
            ;;
        global-50 | global | g50 | tier-global-50 | global-50-auto | global-auto | g50-auto | tier-global-50-auto | global-ms10 | ms10 | tier-global-ms10 | global-ms10-auto | ms10-auto | tier-global-ms10-auto)
            echo "tier_global_ms10"
            return 0
            ;;
        custom)
            echo "custom"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_auto_domain_profile_alias() {
    local raw="${1:-}"
    local value="${raw,,}"
    value="${value// /}"
    value="${value//_/-}"
    case "$value" in
        ru-auto | russia-auto | rf-auto | tier-ru-auto | global-50-auto | global-auto | g50-auto | tier-global-50-auto | global-ms10-auto | ms10-auto | tier-global-ms10-auto)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_legacy_global_profile_alias() {
    local raw="${1:-}"
    local value="${raw,,}"
    value="${value// /}"
    value="${value//_/-}"
    case "$value" in
        global-ms10 | ms10 | tier-global-ms10 | global-ms10-auto | ms10-auto | tier-global-ms10-auto)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

max_configs_for_tier() {
    local tier_raw="${1:-tier_ru}"
    local tier
    if ! tier=$(normalize_domain_tier "$tier_raw"); then
        tier="tier_ru"
    fi
    case "$tier" in
        tier_global_ms10) echo 15 ;;
        *) echo 100 ;;
    esac
}

domain_tier_label() {
    local tier_raw="${1:-tier_ru}"
    local tier
    if ! tier=$(normalize_domain_tier "$tier_raw"); then
        tier="tier_ru"
    fi
    case "$tier" in
        tier_global_ms10) echo "global-50" ;;
        custom) echo "custom" ;;
        *) echo "ru" ;;
    esac
}

LIB_VALIDATION_MODULE="$MODULE_DIR/modules/lib/validation.sh"
if [[ ! -f "$LIB_VALIDATION_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_VALIDATION_MODULE="$XRAY_DATA_DIR/modules/lib/validation.sh"
fi
if [[ ! -f "$LIB_VALIDATION_MODULE" ]]; then
    log ERROR "Не найден модуль валидации: $LIB_VALIDATION_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_VALIDATION_MODULE"

LIB_USAGE_MODULE="$MODULE_DIR/modules/lib/usage.sh"
if [[ ! -f "$LIB_USAGE_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_USAGE_MODULE="$XRAY_DATA_DIR/modules/lib/usage.sh"
fi
if [[ ! -f "$LIB_USAGE_MODULE" ]]; then
    log ERROR "Не найден модуль usage: $LIB_USAGE_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_USAGE_MODULE"

LIB_CLI_MODULE="$MODULE_DIR/modules/lib/cli.sh"
if [[ ! -f "$LIB_CLI_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_CLI_MODULE="$XRAY_DATA_DIR/modules/lib/cli.sh"
fi
if [[ ! -f "$LIB_CLI_MODULE" ]]; then
    log ERROR "Не найден модуль CLI: $LIB_CLI_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_CLI_MODULE"

LIB_POLICY_MODULE="$MODULE_DIR/modules/lib/policy.sh"
if [[ ! -f "$LIB_POLICY_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_POLICY_MODULE="$XRAY_DATA_DIR/modules/lib/policy.sh"
fi
if [[ ! -f "$LIB_POLICY_MODULE" ]]; then
    log ERROR "Не найден модуль policy: $LIB_POLICY_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_POLICY_MODULE"

LIB_CONTRACT_GATE_MODULE="$MODULE_DIR/modules/lib/contract_gate.sh"
if [[ ! -f "$LIB_CONTRACT_GATE_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_CONTRACT_GATE_MODULE="$XRAY_DATA_DIR/modules/lib/contract_gate.sh"
fi
if [[ ! -f "$LIB_CONTRACT_GATE_MODULE" ]]; then
    log ERROR "Не найден модуль contract gate: $LIB_CONTRACT_GATE_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_CONTRACT_GATE_MODULE"

LIB_CONFIG_LOADING_MODULE="$MODULE_DIR/modules/lib/config_loading.sh"
if [[ ! -f "$LIB_CONFIG_LOADING_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_CONFIG_LOADING_MODULE="$XRAY_DATA_DIR/modules/lib/config_loading.sh"
fi
if [[ ! -f "$LIB_CONFIG_LOADING_MODULE" ]]; then
    log ERROR "Не найден модуль config loading: $LIB_CONFIG_LOADING_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_CONFIG_LOADING_MODULE"

LIB_PATH_SAFETY_MODULE="$MODULE_DIR/modules/lib/path_safety.sh"
if [[ ! -f "$LIB_PATH_SAFETY_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_PATH_SAFETY_MODULE="$XRAY_DATA_DIR/modules/lib/path_safety.sh"
fi
if [[ ! -f "$LIB_PATH_SAFETY_MODULE" ]]; then
    log ERROR "Не найден модуль path safety: $LIB_PATH_SAFETY_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_PATH_SAFETY_MODULE"

LIB_RUNTIME_INPUTS_MODULE="$MODULE_DIR/modules/lib/runtime_inputs.sh"
if [[ ! -f "$LIB_RUNTIME_INPUTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_RUNTIME_INPUTS_MODULE="$XRAY_DATA_DIR/modules/lib/runtime_inputs.sh"
fi
if [[ ! -f "$LIB_RUNTIME_INPUTS_MODULE" ]]; then
    log ERROR "Не найден модуль runtime inputs: $LIB_RUNTIME_INPUTS_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_RUNTIME_INPUTS_MODULE"

LIB_RUNTIME_REUSE_MODULE="$MODULE_DIR/modules/lib/runtime_reuse.sh"
if [[ ! -f "$LIB_RUNTIME_REUSE_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_RUNTIME_REUSE_MODULE="$XRAY_DATA_DIR/modules/lib/runtime_reuse.sh"
fi
if [[ ! -f "$LIB_RUNTIME_REUSE_MODULE" ]]; then
    log ERROR "Не найден модуль runtime reuse: $LIB_RUNTIME_REUSE_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_RUNTIME_REUSE_MODULE"

LIB_DOMAIN_SOURCES_MODULE="$MODULE_DIR/modules/lib/domain_sources.sh"
if [[ ! -f "$LIB_DOMAIN_SOURCES_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_DOMAIN_SOURCES_MODULE="$XRAY_DATA_DIR/modules/lib/domain_sources.sh"
fi
if [[ ! -f "$LIB_DOMAIN_SOURCES_MODULE" ]]; then
    log ERROR "Не найден модуль источников доменов: $LIB_DOMAIN_SOURCES_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_DOMAIN_SOURCES_MODULE"

LIB_FIREWALL_MODULE="$MODULE_DIR/modules/lib/firewall.sh"
if [[ ! -f "$LIB_FIREWALL_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_FIREWALL_MODULE="$XRAY_DATA_DIR/modules/lib/firewall.sh"
fi
if [[ ! -f "$LIB_FIREWALL_MODULE" ]]; then
    log ERROR "Не найден модуль firewall: $LIB_FIREWALL_MODULE"
    exit 1
fi
# shellcheck source=modules/lib/firewall.sh
source "$LIB_FIREWALL_MODULE"

LIB_LIFECYCLE_MODULE="$MODULE_DIR/modules/lib/lifecycle.sh"
if [[ ! -f "$LIB_LIFECYCLE_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LIB_LIFECYCLE_MODULE="$XRAY_DATA_DIR/modules/lib/lifecycle.sh"
fi
if [[ ! -f "$LIB_LIFECYCLE_MODULE" ]]; then
    log ERROR "Не найден модуль lifecycle: $LIB_LIFECYCLE_MODULE"
    exit 1
fi
# shellcheck source=modules/lib/lifecycle.sh
source "$LIB_LIFECYCLE_MODULE"
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "Запустите скрипт с правами root:"
        echo -e "  ${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
}

require_systemd_runtime_for_action() {
    local action="${1:-$ACTION}"
    case "$action" in
        install | update | repair | migrate-stealth | add-clients | add-keys) ;;
        *)
            return 0
            ;;
    esac

    if [[ "$action" == "add-clients" || "$action" == "add-keys" ]]; then
        if ! systemctl_available; then
            log ERROR "Для действия '${action}' требуется systemd (команда systemctl не найдена)"
            return 1
        fi
        if ! systemd_running; then
            if running_in_isolated_root_context; then
                log ERROR "Для действия '${action}' требуется systemd (обнаружен chroot/isolated root context)"
            else
                log ERROR "Для действия '${action}' требуется активный systemd (PID 1 = systemd)"
            fi
            return 1
        fi
        return 0
    fi

    if [[ "$ALLOW_NO_SYSTEMD" == "true" ]]; then
        if ! systemctl_available || ! systemd_running; then
            log WARN "Включён режим совместимости без systemd (--allow-no-systemd)"
            log WARN "Часть действий (service/timer/auto-update) будет пропущена"
        fi
        return 0
    fi

    if ! systemctl_available; then
        log ERROR "Для действия '${action}' требуется systemd (команда systemctl не найдена)"
        log ERROR "Запустите на системе с systemd или добавьте --allow-no-systemd"
        return 1
    fi
    if ! systemd_running; then
        if running_in_isolated_root_context; then
            log ERROR "Для действия '${action}' требуется systemd (обнаружен chroot/isolated root context)"
        else
            log ERROR "Для действия '${action}' требуется активный systemd (PID 1 = systemd)"
        fi
        log ERROR "Используйте --allow-no-systemd только если понимаете ограничения"
        return 1
    fi
    return 0
}

main() {
    parse_args "$@"
    if [[ -z "$XRAY_CONFIG_FILE" && "$ACTION" != "install" && -f "$XRAY_ENV" ]]; then
        XRAY_CONFIG_FILE="$XRAY_ENV"
    fi
    load_config_file "$XRAY_CONFIG_FILE"
    if [[ -f "$XRAY_POLICY" ]]; then
        load_policy_file "$XRAY_POLICY"
    fi
    if [[ "$ACTION" != "install" && -f "$XRAY_ENV" ]]; then
        load_runtime_identity_defaults "$XRAY_ENV"
    fi
    apply_runtime_overrides

    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_summary
        exit 0
    fi

    case "$ACTION" in
        install)
            strict_validate_runtime_inputs "install"
            require_root
            require_systemd_runtime_for_action "install"
            require_xhttp_transport_contract_for_action "install"
            install_flow
            ;;
        add-clients)
            strict_validate_runtime_inputs "add-clients"
            require_root
            require_systemd_runtime_for_action "add-clients"
            require_xhttp_transport_contract_for_action "add-clients"
            add_clients_flow
            ;;
        add-keys)
            strict_validate_runtime_inputs "add-keys"
            require_root
            require_systemd_runtime_for_action "add-keys"
            require_xhttp_transport_contract_for_action "add-keys"
            add_clients_flow
            ;;
        update)
            strict_validate_runtime_inputs "update"
            require_root
            require_systemd_runtime_for_action "update"
            require_xhttp_transport_contract_for_action "update"
            update_flow
            ;;
        repair)
            strict_validate_runtime_inputs "repair"
            require_root
            require_systemd_runtime_for_action "repair"
            require_xhttp_transport_contract_for_action "repair"
            repair_flow
            ;;
        migrate-stealth)
            strict_validate_runtime_inputs "migrate-stealth"
            require_root
            require_systemd_runtime_for_action "migrate-stealth"
            migrate_stealth_flow
            ;;
        diagnose)
            strict_validate_runtime_inputs "diagnose"
            require_root
            diagnose_flow
            ;;
        rollback)
            strict_validate_runtime_inputs "rollback"
            require_root
            rollback_flow
            ;;
        uninstall)
            strict_validate_runtime_inputs "uninstall"
            require_root
            uninstall_flow
            ;;
        status)
            status_flow
            ;;
        logs)
            logs_flow
            ;;
        check-update)
            check_update_flow
            ;;
        *)
            log ERROR "Неизвестное действие: $ACTION"
            print_usage
            exit 1
            ;;
    esac
}
record_created_path() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 0
    local resolved
    resolved=$(realpath -m "$path" 2> /dev/null || echo "$path")
    if [[ -n "${CREATED_PATH_SET[$resolved]:-}" ]]; then
        return 0
    fi
    CREATED_PATH_SET["$resolved"]=1
    CREATED_PATHS+=("$resolved")
}
