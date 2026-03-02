#!/usr/bin/env bash
# Network Stealth Core 4.2.0 - Автоматизация установки и сопровождения Xray Reality (gRPC/HTTP2 + Reality + MUX)

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

readonly SCRIPT_VERSION="4.2.0"
readonly SCRIPT_NAME="Network Stealth Core"

XRAY_USER="xray"
XRAY_GROUP="xray"
XRAY_HOME="${XRAY_HOME:-/var/lib/xray}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_GEO_DIR="${XRAY_GEO_DIR:-}"
XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/config.json}"
XRAY_ENV="${XRAY_ENV:-/etc/xray-reality/config.env}"
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
TRANSPORT="${TRANSPORT:-grpc}" # grpc|http2
MUX_MODE="${MUX_MODE:-on}"     # on|off|auto (on = максимальная обфускация)
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
XRAY_GRPC_SERVICES_FILE="${XRAY_GRPC_SERVICES_FILE:-}"
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
DOWNLOAD_HOST_ALLOWLIST="${DOWNLOAD_HOST_ALLOWLIST:-github.com,api.github.com,objects.githubusercontent.com,raw.githubusercontent.com,release-assets.githubusercontent.com,ghproxy.com}"
GH_PROXY_BASE="${GH_PROXY_BASE:-https://ghproxy.com/https://github.com}"
ACTION="install"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
AUTO_PROFILE_MODE="${AUTO_PROFILE_MODE:-false}"
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
CONFIG_GRPC_SERVICES=()
CONFIG_FPS=()
AVAILABLE_DOMAINS=()
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
: "${CONFIG_DOMAINS[@]}" "${CONFIG_SNIS[@]}" "${CONFIG_GRPC_SERVICES[@]}" "${CONFIG_FPS[@]}" "${AVAILABLE_DOMAINS[@]}"

DEFAULT_DATA_DIR="/usr/local/share/xray-reality"
if [[ -z "${XRAY_DATA_DIR:-}" ]]; then
    XRAY_DATA_DIR="$DEFAULT_DATA_DIR"
fi
export XRAY_DATA_DIR
XRAY_TIERS_FILE="${XRAY_TIERS_FILE:-$XRAY_DATA_DIR/domains.tiers}"
XRAY_SNI_POOLS_FILE="${XRAY_SNI_POOLS_FILE:-$XRAY_DATA_DIR/sni_pools.map}"
XRAY_GRPC_SERVICES_FILE="${XRAY_GRPC_SERVICES_FILE:-$XRAY_DATA_DIR/grpc_services.map}"

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

    local custom_path tty_fd
    if ! open_interactive_tty_fd tty_fd; then
        log ERROR "Терминал /dev/tty недоступен: невозможно запросить путь вручную"
        return 1
    fi
    while true; do
        if ! tty_printf "$tty_fd" '  Укажите путь вручную для %s: ' "$description"; then
            exec {tty_fd}>&-
            log ERROR "Не удалось вывести приглашение ввода пути в /dev/tty"
            return 1
        fi
        if ! read -r -u "$tty_fd" custom_path; then
            exec {tty_fd}>&-
            log ERROR "Не удалось прочитать путь из /dev/tty"
            return 1
        fi
        custom_path=$(normalize_tty_input "$custom_path")
        if [[ -z "$custom_path" ]]; then
            tty_printf "$tty_fd" '  %bПуть не может быть пустым%b\n' "$RED" "$NC"
            continue
        fi
        if _try_file_path "$custom_path" || _try_dir "$custom_path"; then
            exec {tty_fd}>&-
            printf -v "$var_name" '%s' "$custom_path"
            log OK "${description}: используем ${custom_path}"
            return 0
        fi
        tty_printf "$tty_fd" '  %bПуть %s недоступен для записи%b\n' "$RED" "$custom_path" "$NC"
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
    XRAY_GRPC_SERVICES_FILE="$XRAY_DATA_DIR/grpc_services.map"

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

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

UI_GLYPHS_INITIALIZED=false
UI_BOX_TL="+"
UI_BOX_TR="+"
UI_BOX_BL="+"
UI_BOX_BR="+"
UI_BOX_V="|"
UI_BOX_H="-"
UI_RULE_H="-"

ui_supports_unicode() {
    local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ -t 1 ]] || return 1
    [[ "$locale" =~ [Uu][Tt][Ff]-?8 ]]
}

ui_init_glyphs() {
    if [[ "${UI_GLYPHS_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi
    if ui_supports_unicode; then
        UI_BOX_TL="╔"
        UI_BOX_TR="╗"
        UI_BOX_BL="╚"
        UI_BOX_BR="╝"
        UI_BOX_V="║"
        UI_BOX_H="═"
        UI_RULE_H="━"
    else
        UI_BOX_TL="+"
        UI_BOX_TR="+"
        UI_BOX_BL="+"
        UI_BOX_BR="+"
        UI_BOX_V="|"
        UI_BOX_H="-"
        UI_RULE_H="-"
    fi
    UI_GLYPHS_INITIALIZED=true
}

ui_repeat_char() {
    local ch="$1"
    local count="$2"
    local out=""
    local i
    for ((i = 0; i < count; i++)); do
        out+="$ch"
    done
    printf '%s' "$out"
}

ui_box_sanitize_text() {
    local text="${1:-}"
    text="${text//$'\r'/ }"
    text="${text//$'\n'/ }"
    text="${text//$'\t'/ }"
    printf '%s' "$text"
}

normalize_tty_input() {
    local value="${1:-}"
    # Drop common terminal control artifacts (for example bracketed paste markers).
    value="${value//$'\e[200~'/}"
    value="${value//$'\e[201~'/}"
    value="${value//$'\r\n'/$'\n'}"
    value="${value//$'\r'/}"

    # Remove OSC sequences (ESC ] ... BEL or ESC ] ... ESC \).
    while [[ "$value" == *$'\e]'* ]]; do
        local osc_prefix osc_tail
        osc_prefix="${value%%$'\e]'*}"
        osc_tail="${value#*$'\e]'}"
        if [[ "$osc_tail" == *$'\a'* ]]; then
            osc_tail="${osc_tail#*$'\a'}"
        elif [[ "$osc_tail" == *$'\e\\'* ]]; then
            osc_tail="${osc_tail#*$'\e\\'}"
        else
            osc_tail=""
        fi
        value="${osc_prefix}${osc_tail}"
    done

    # Remove CSI/SS3 and remaining one-byte ESC controls.
    value=$(printf '%s' "$value" | sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g; s/\x1BO[ -~]//g; s/\x1B[@-_]//g')

    # Remove common zero-width/BiDi artifacts and non-printable control bytes.
    value="${value//$'\u00A0'/ }"
    value="${value//$'\u200B'/}"
    value="${value//$'\u200C'/}"
    value="${value//$'\u200D'/}"
    value="${value//$'\u200E'/}"
    value="${value//$'\u200F'/}"
    value="${value//$'\u202A'/}"
    value="${value//$'\u202B'/}"
    value="${value//$'\u202C'/}"
    value="${value//$'\u202D'/}"
    value="${value//$'\u202E'/}"
    value="${value//$'\u2060'/}"
    value="${value//$'\u2066'/}"
    value="${value//$'\u2067'/}"
    value="${value//$'\u2068'/}"
    value="${value//$'\u2069'/}"
    value="${value//$'\uFEFF'/}"
    value=$(printf '%s' "$value" | tr -d '\000-\010\013\014\016-\037\177')
    value=$(trim_ws "$value")
    printf '%s' "$value"
}

open_interactive_tty_fd() {
    local out_var="${1:-}"
    [[ -n "$out_var" ]] || return 1

    local opened_fd=""
    if ! exec {opened_fd}<> /dev/tty 2> /dev/null; then
        return 1
    fi
    printf -v "$out_var" '%s' "$opened_fd"
    return 0
}

tty_printf() {
    local tty_fd="${1:-}"
    shift || true
    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1
    # shellcheck disable=SC2059 # Controlled internal helper: callers pass static format strings.
    printf "$@" >&"$tty_fd"
}

tty_print_line() {
    local tty_fd="${1:-}"
    shift || true
    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$*" >&"$tty_fd"
}

tty_print_box() {
    local tty_fd="${1:-}"
    local color="${2:-$NC}"
    local title="${3:-}"
    local min_width="${4:-60}"
    local max_width="${5:-90}"

    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 1

    local width top line bottom
    width=$(ui_box_width_for_lines "$min_width" "$max_width" "$title")
    top=$(ui_box_border_string top "$width")
    line=$(ui_box_line_string "$title" "$width")
    bottom=$(ui_box_border_string bottom "$width")

    tty_printf "$tty_fd" '%b%s%b\n' "${BOLD}${color}" "$top" "$NC"
    tty_printf "$tty_fd" '%b%s%b\n' "${BOLD}${color}" "$line" "$NC"
    tty_printf "$tty_fd" '%b%s%b\n' "${BOLD}${color}" "$bottom" "$NC"
}

canonicalize_confirmation_token() {
    local value
    value=$(normalize_tty_input "${1:-}")
    # Normalize known uppercase Cyrillic symbols explicitly (locale-agnostic).
    value="${value//Ё/e}"
    value="${value//Е/e}"
    value="${value//О/o}"
    value="${value//У/y}"
    value="${value//С/s}"
    value="${value//Ѕ/s}"
    value="${value//Н/n}"
    value="${value//Д/d}"
    value="${value//А/a}"
    value="${value//Т/t}"
    value="${value,,}"
    # Normalize mixed-layout lookalikes, then keep ASCII letters/digits only.
    value="${value//ё/e}"
    value="${value//е/e}"
    value="${value//о/o}"
    value="${value//у/y}"
    value="${value//с/s}"
    value="${value//ѕ/s}"
    value="${value//н/n}"
    value="${value//д/d}"
    value="${value//а/a}"
    value="${value//т/t}"
    value=$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+//g')
    printf '%s' "$value"
}

normalize_yes_no_token() {
    local value
    value=$(canonicalize_confirmation_token "${1:-}")
    printf '%s' "$value"
}

normalize_yes_token_hint() {
    local value
    value=$(canonicalize_confirmation_token "${1:-}")
    printf '%s' "$value"
}

is_yes_input() {
    local value
    value=$(canonicalize_confirmation_token "${1:-}")
    case "$value" in
        yes | y | da | d) return 0 ;;
        *) return 1 ;;
    esac
}

is_no_input() {
    local value
    value=$(canonicalize_confirmation_token "${1:-}")
    case "$value" in
        no | n | net) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_yes_no_from_tty() {
    local tty_fd="${1:-}"
    local prompt_text="${2:-}"
    local retry_text="${3:-Введите yes или no}"
    local answer normalized

    [[ "$tty_fd" =~ ^[0-9]+$ ]] || return 2

    while true; do
        if ! tty_printf "$tty_fd" '%s' "$prompt_text"; then
            return 2
        fi
        if ! read -r -u "$tty_fd" answer; then
            return 2
        fi
        normalized=$(normalize_tty_input "$answer")
        if is_yes_input "$normalized"; then
            return 0
        fi
        if [[ -z "$normalized" ]] || is_no_input "$normalized"; then
            return 1
        fi
        if ! tty_printf "$tty_fd" '%s\n' "$retry_text"; then
            return 2
        fi
    done
}

ui_box_fit_text() {
    local text="${1:-}"
    local width="${2:-60}"
    if ! [[ "$width" =~ ^[0-9]+$ ]] || ((width < 1)); then
        width=1
    fi

    local sanitized
    sanitized=$(ui_box_sanitize_text "$text")

    if ((${#sanitized} <= width)); then
        printf '%s' "$sanitized"
        return 0
    fi

    if ((width <= 3)); then
        printf '%s' "${sanitized:0:width}"
        return 0
    fi

    printf '%s...' "${sanitized:0:$((width - 3))}"
}

ui_box_width_for_lines() {
    local min_width="${1:-60}"
    local max_width="${2:-80}"
    shift 2 || true

    if ! [[ "$min_width" =~ ^[0-9]+$ ]] || ((min_width < 1)); then
        min_width=1
    fi
    if ! [[ "$max_width" =~ ^[0-9]+$ ]] || ((max_width < min_width)); then
        max_width="$min_width"
    fi

    local desired="$min_width"
    local line sanitized line_len
    for line in "$@"; do
        sanitized=$(ui_box_sanitize_text "$line")
        line_len=${#sanitized}
        if ((line_len > desired)); then
            desired="$line_len"
        fi
    done

    if ((desired > max_width)); then
        desired="$max_width"
    fi
    printf '%s' "$desired"
}

ui_box_border_string() {
    local kind="${1:-top}"
    local width="${2:-60}"
    ui_init_glyphs
    case "$kind" in
        top) printf '%s%s%s' "$UI_BOX_TL" "$(ui_repeat_char "$UI_BOX_H" "$width")" "$UI_BOX_TR" ;;
        bottom) printf '%s%s%s' "$UI_BOX_BL" "$(ui_repeat_char "$UI_BOX_H" "$width")" "$UI_BOX_BR" ;;
        *) return 1 ;;
    esac
}

ui_box_line_string() {
    local text="${1:-}"
    local width="${2:-60}"
    local fitted
    local pad_len
    local pad
    ui_init_glyphs
    fitted=$(ui_box_fit_text "$text" "$width")
    pad_len=$((width - ${#fitted}))
    if ((pad_len < 0)); then
        pad_len=0
    fi
    pad=$(ui_repeat_char " " "$pad_len")
    printf '%s%s%s%s' "$UI_BOX_V" "$fitted" "$pad" "$UI_BOX_V"
}

ui_rule_string() {
    local width="${1:-58}"
    ui_init_glyphs
    ui_repeat_char "$UI_RULE_H" "$width"
}

ui_section_title_string() {
    local title="${1:-}"
    ui_init_glyphs
    if [[ "$UI_RULE_H" == "━" ]]; then
        printf -- '━━━ %s ━━━' "$title"
    else
        printf -- '--- %s ---' "$title"
    fi
}

setup_logging() {
    local log_dir
    log_dir=$(dirname "$INSTALL_LOG")
    mkdir -p "$log_dir"

    if [[ "${LOGGING_BACKEND:-none}" == "none" ]]; then
        local tmp_base fifo_path
        tmp_base="${TMPDIR:-/tmp}"
        if [[ ! -d "$tmp_base" || ! -w "$tmp_base" ]]; then
            tmp_base="/tmp"
        fi

        local fifo_dir=""
        fifo_dir=$(mktemp -d "${tmp_base}/xray-log.XXXXXX" 2> /dev/null || true)
        if [[ -n "$fifo_dir" ]]; then
            fifo_path="${fifo_dir}/stream"
        fi

        if [[ -n "$fifo_path" ]] && mkfifo -m 600 "$fifo_path" 2> /dev/null; then
            exec {LOGGING_STDOUT_FD}>&1
            exec {LOGGING_STDERR_FD}>&2
            tee -a "$INSTALL_LOG" < "$fifo_path" >&"$LOGGING_STDOUT_FD" &
            LOGGING_TEE_PID="$!"
            LOGGING_FIFO="$fifo_path"
            exec > "$fifo_path" 2>&1
            rm -f "$fifo_path"
            if [[ -n "$fifo_dir" ]]; then
                rmdir "$fifo_dir" 2> /dev/null || true
            fi
            LOGGING_FIFO=""
            LOGGING_BACKEND="fifo"
        else
            if [[ -n "$fifo_dir" ]]; then
                rm -rf "$fifo_dir" 2> /dev/null || true
            fi
            exec > >(tee -a "$INSTALL_LOG")
            exec 2>&1
            LOGGING_BACKEND="process_subst"
        fi
    fi

    local inner_width
    local title="${SCRIPT_NAME} v${SCRIPT_VERSION}"
    local subtitle="Автоматизация установки и сопровождения Xray Reality (gRPC/HTTP2 + Reality + MUX)"
    inner_width=$(ui_box_width_for_lines 60 92 "$title" "$subtitle")
    local box_top box_bottom
    box_top=$(ui_box_border_string top "$inner_width")
    box_bottom=$(ui_box_border_string bottom "$inner_width")
    local box_title box_subtitle
    box_title=$(ui_box_line_string "$title" "$inner_width")
    box_subtitle=$(ui_box_line_string "$subtitle" "$inner_width")

    echo "$box_top"
    echo -e "${BOLD}${box_title}${NC}"
    echo "$box_subtitle"
    echo "$box_bottom"
    echo ""
    printf '📝 Начало %s: %s\n\n' "$LOG_CONTEXT" "$(date '+%Y-%m-%d %H:%M:%S')"
}

sanitize_log_message() {
    local input="$*"
    if [[ -z "$input" ]]; then
        echo ""
        return 0
    fi

    printf '%s' "$input" | sed -E \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/UUID-REDACTED/g' \
        -e 's/("privateKey"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g' \
        -e 's/("password"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g' \
        -e 's/(Private Key:[[:space:]]*)[^[:space:]]+/\1***REDACTED***/g' \
        -e 's/([?&](pbk|sid|password|token|privateKey)=)[^&#[:space:]]+/\1***REDACTED***/gI' \
        -e 's#vless://[^[:space:]]+#VLESS-REDACTED#gI' \
        -e 's/(password[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1***REDACTED***/gI'
}

log() {
    local level="$1"
    shift
    local icon=""
    local color="${NC}"
    local message="$*"

    case "$level" in
        DEBUG)
            [[ "$VERBOSE" == "true" ]] || return 0
            icon="•"
            color="${DIM}"
            ;;
        INFO)
            icon="ℹ️ "
            color="${BLUE}"
            ;;
        OK)
            icon="✅"
            color="${GREEN}"
            ;;
        WARN)
            icon="⚠️ "
            color="${YELLOW}"
            ;;
        ERROR)
            icon="❌"
            color="${RED}"
            ;;
        STEP)
            icon="▶️ "
            color="${CYAN}"
            ;;
        *)
            icon="•"
            color="${NC}"
            ;;
    esac

    local sanitized_message
    sanitized_message=$(sanitize_log_message "$message")
    if [[ "${PROGRESS_LINE_OPEN:-false}" == "true" ]]; then
        printf '\r\033[K\n'
        PROGRESS_LINE_OPEN=false
    fi
    echo -e "${color}${icon} ${sanitized_message}${NC}"
}

debug() {
    log DEBUG "$@"
}

debug_file() {
    local msg="$*"
    msg=$(sanitize_log_message "$msg")
    if [[ -n "${INSTALL_LOG:-}" && -w "$(dirname "${INSTALL_LOG}")" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $msg" >> "$INSTALL_LOG"
    fi
}

cleanup_logging_processes() {
    local backend="${LOGGING_BACKEND:-none}"
    if [[ "$backend" == "none" ]]; then
        return 0
    fi

    if [[ "$backend" == "fifo" ]]; then
        if [[ -n "${LOGGING_STDOUT_FD:-}" && -n "${LOGGING_STDERR_FD:-}" ]]; then
            exec 1>&"$LOGGING_STDOUT_FD" 2>&"$LOGGING_STDERR_FD"
            exec {LOGGING_STDOUT_FD}>&-
            exec {LOGGING_STDERR_FD}>&-
            LOGGING_STDOUT_FD=""
            LOGGING_STDERR_FD=""
        fi
        if [[ -n "${LOGGING_TEE_PID:-}" && "$LOGGING_TEE_PID" =~ ^[0-9]+$ ]]; then
            wait "$LOGGING_TEE_PID" 2> /dev/null || true
        fi
        if [[ -n "${LOGGING_FIFO:-}" && -p "${LOGGING_FIFO}" ]]; then
            rm -f "$LOGGING_FIFO" 2> /dev/null || true
        fi
        LOGGING_TEE_PID=""
        LOGGING_FIFO=""
        LOGGING_BACKEND="none"
        return 0
    fi

    if command -v pgrep > /dev/null 2>&1; then
        local -a tee_pids=()
        mapfile -t tee_pids < <(pgrep -P $$ -x tee || true)
        local pid
        for pid in "${tee_pids[@]}"; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            kill "$pid" 2> /dev/null || true
            wait "$pid" 2> /dev/null || true
        done
    fi
    LOGGING_BACKEND="none"
}

print_secret_file_to_tty() {
    local file="$1"
    local label="${2:-секретные данные}"
    local fallback_file="${3:-$file}"

    [[ -f "$file" ]] || return 1
    if can_write_dev_tty; then
        if {
            cat "$file"
            echo ""
        } > /dev/tty 2> /dev/null; then
            log INFO "${label} выведены только в /dev/tty (в install log не записаны)"
            return 0
        fi
    fi

    log INFO "Терминал недоступен; ${label} не печатаются в лог. Откройте файл: ${fallback_file}"
    return 1
}

can_write_dev_tty() {
    [[ -e /dev/tty && -w /dev/tty ]] || return 1
    tty -s 2> /dev/null || return 1
    { :; } > /dev/tty 2> /dev/null || return 1
    return 0
}

hint() {
    if [[ "${PROGRESS_LINE_OPEN:-false}" == "true" ]]; then
        printf '\r\033[K\n'
        PROGRESS_LINE_OPEN=false
    fi
    echo -e "  ${DIM}💡 Подсказка: $*${NC}"
}

resolve_progress_mode() {
    local mode="${PROGRESS_MODE:-${XRAY_PROGRESS_MODE:-auto}}"
    mode=$(trim_ws "${mode,,}")
    [[ -z "$mode" ]] && mode="auto"
    [[ "$mode" == "off" ]] && mode="none"

    if [[ -n "${PROGRESS_RENDER_MODE:-}" && "${PROGRESS_RENDER_MODE_SOURCE:-}" == "$mode" ]]; then
        printf '%s\n' "$PROGRESS_RENDER_MODE"
        return 0
    fi

    case "$mode" in
        bar | plain | none)
            PROGRESS_RENDER_MODE="$mode"
            ;;
        auto)
            if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
                PROGRESS_RENDER_MODE="plain"
            else
                local cols=0
                if command -v tput > /dev/null 2>&1; then
                    cols=$(tput cols 2> /dev/null || echo 0)
                fi
                if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0 && cols < 120)); then
                    PROGRESS_RENDER_MODE="plain"
                else
                    PROGRESS_RENDER_MODE="bar"
                fi
            fi
            ;;
        *)
            if [[ "${PROGRESS_MODE_WARNED:-false}" != "true" ]]; then
                log WARN "Некорректный PROGRESS_MODE: ${mode} (используем auto)"
                PROGRESS_MODE_WARNED=true
            fi
            PROGRESS_RENDER_MODE="bar"
            mode="auto"
            ;;
    esac

    PROGRESS_RENDER_MODE_SOURCE="$mode"
    printf '%s\n' "$PROGRESS_RENDER_MODE"
}

progress_bar() {
    local current="$1"
    local total="$2"
    if [[ ! "$current" =~ ^[0-9]+$ ]] || [[ ! "$total" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$total" -le 0 ]]; then
        return 0
    fi

    local mode
    mode=$(resolve_progress_mode)
    local percentage=$((current * 100 / total))

    if [[ "$mode" == "none" ]]; then
        PROGRESS_LINE_OPEN=false
        if ((current == total)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        return 0
    fi

    if [[ "$mode" == "plain" ]]; then
        if ((current <= 1)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        if ((percentage != PROGRESS_LAST_PERCENT || current == total)); then
            printf '%b[%3d%%] %d/%d%b\n' "$CYAN" "$percentage" "$current" "$total" "$NC"
            PROGRESS_LAST_PERCENT=$percentage
        fi
        PROGRESS_LINE_OPEN=false
        if ((current == total)); then
            PROGRESS_LAST_PERCENT=-1
        fi
        return 0
    fi

    local width=40
    local filled=$((width * current / total))
    local empty=$((width - filled))
    local fill_char="█"
    local empty_char="░"
    local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$locale" != *[Uu][Tt][Ff]-8* && "$locale" != *[Uu][Tt][Ff]8* ]]; then
        fill_char="#"
        empty_char="-"
    fi

    local bar
    printf '\r\033[K%b[' "$CYAN"
    bar=$(printf "%${filled}s")
    bar=${bar// /$fill_char}
    printf "%s" "$bar"
    bar=$(printf "%${empty}s")
    bar=${bar// /$empty_char}
    printf "%s" "$bar"
    printf '] %3d%% %b' "$percentage" "$NC"

    if [[ $current -eq $total ]]; then
        echo ""
        PROGRESS_LINE_OPEN=false
        PROGRESS_LAST_PERCENT=-1
    else
        PROGRESS_LINE_OPEN=true
    fi
    return 0
}

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

resolve_mirror_base() {
    local base="$1"
    local version="$2"
    base=$(trim_ws "$base")
    base="${base//\{\{version\}\}/$version}"
    base="${base//\{version\}/$version}"
    base="${base//\$version/$version}"
    printf '%s' "${base%/}"
}

build_mirror_list() {
    local default_base="$1"
    local extra="$2"
    local version="$3"
    local -a mirrors=()
    local item
    if [[ -n "$default_base" ]]; then
        mirrors+=("$(resolve_mirror_base "$default_base" "$version")")
    fi
    while read -r item; do
        item=$(trim_ws "$item")
        [[ -z "$item" ]] && continue
        mirrors+=("$(resolve_mirror_base "$item" "$version")")
    done < <(split_list "$extra")
    printf '%s\n' "${mirrors[@]}"
}

xray_geo_dir() {
    if [[ -n "${XRAY_GEO_DIR:-}" ]]; then
        printf '%s\n' "$XRAY_GEO_DIR"
        return 0
    fi
    printf '%s\n' "$(dirname "$XRAY_BIN")"
}

url_host_from_https() {
    local url="$1"
    local rest="${url#https://}"
    rest="${rest%%/*}"
    rest="${rest%%\?*}"
    rest="${rest%%#*}"
    rest="${rest%%:*}"
    printf '%s' "${rest,,}"
}

is_valid_https_url() {
    local url="$1"
    [[ -n "$url" ]] || return 1
    [[ "$url" == https://* ]] || return 1
    [[ "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 1
    [[ ! "$url" =~ [[:cntrl:][:space:]] ]] || return 1

    local host
    host=$(url_host_from_https "$url")
    [[ -n "$host" ]] || return 1
    [[ "$host" =~ ^[a-z0-9.-]+$ ]] || return 1
    [[ "$host" != .* && "$host" != *..* && "$host" != *- && "$host" != -* ]] || return 1
    return 0
}

is_allowlisted_download_host() {
    local host="${1,,}"
    local entry
    while read -r entry; do
        entry=$(trim_ws "${entry,,}")
        [[ -n "$entry" ]] || continue
        if [[ "$host" == "$entry" || "$host" == *".${entry}" ]]; then
            return 0
        fi
    done < <(split_list "$DOWNLOAD_HOST_ALLOWLIST")
    return 1
}

validate_curl_target() {
    local url="$1"
    local require_allowlist="${2:-false}"

    if ! is_valid_https_url "$url"; then
        log ERROR "Невалидный URL для загрузки: $url"
        return 1
    fi

    if [[ "$require_allowlist" == "true" ]]; then
        local host
        host=$(url_host_from_https "$url")
        if ! is_allowlisted_download_host "$host"; then
            log ERROR "Хост не в DOWNLOAD_HOST_ALLOWLIST: $host"
            return 1
        fi
    fi
    return 0
}

resolve_effective_https_url() {
    local url="$1"
    local effective_url
    effective_url=$(curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' \
        --output /dev/null --write-out '%{url_effective}' "$url")
    effective_url=$(trim_ws "$effective_url")
    if [[ -z "$effective_url" ]]; then
        log ERROR "Не удалось определить конечный redirect URL: $url"
        return 1
    fi
    if ! is_valid_https_url "$effective_url"; then
        log ERROR "Невалидный конечный redirect URL: $effective_url"
        return 1
    fi
    printf '%s\n' "$effective_url"
}

resolve_allowlisted_effective_url() {
    local url="$1"
    validate_curl_target "$url" true || return 1
    local effective_url
    if ! effective_url=$(resolve_effective_https_url "$url"); then
        return 1
    fi
    if ! validate_curl_target "$effective_url" true; then
        log ERROR "Конечный redirect URL вне allowlist: $effective_url"
        return 1
    fi
    printf '%s\n' "$effective_url"
}

curl_fetch_text() {
    local url="$1"
    shift
    validate_curl_target "$url" false || return 1
    curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        "$@" "$url"
}

curl_fetch_text_allowlist() {
    local url="$1"
    shift
    local effective_url
    effective_url=$(resolve_allowlisted_effective_url "$url") || return 1
    curl --fail --show-error --silent \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        "$@" "$effective_url"
}

download_file_allowlist() {
    if (($# < 2 || $# > 3)); then
        log ERROR "download_file_allowlist: usage: <url> <out_file> [description]"
        return 1
    fi

    local url="$1"
    local out_file="$2"
    local description="${3:-}"

    if [[ -n "$description" ]]; then
        debug "$description"
    fi

    local effective_url
    effective_url=$(resolve_allowlisted_effective_url "$url") || return 1

    local attempts="${DOWNLOAD_RETRIES:-3}"
    local delay="${DOWNLOAD_RETRY_DELAY:-2}"
    local i rc=1
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/xray-dl.XXXXXX") || {
        log ERROR "Не удалось создать временную директорию для загрузки"
        return 1
    }
    local tmp_file=""

    if [[ ! "$attempts" =~ ^[0-9]+$ ]] || ((attempts < 1)); then
        attempts=1
    fi
    if [[ ! "$delay" =~ ^[0-9]+$ ]] || ((delay < 0)); then
        delay=0
    fi

    (
        trap 'rm -f "${tmp_file:-}"; rm -rf "${tmp_dir:-}"' EXIT INT TERM
        for ((i = 1; i <= attempts; i++)); do
            rm -f "${tmp_file:-}"
            tmp_file=$(mktemp "${tmp_dir}/part.XXXXXX") || {
                rc=1
                break
            }
            if curl --fail --show-error --silent \
                --proto '=https' --proto-redir '=https' --tlsv1.2 \
                --connect-timeout "$CONNECTION_TIMEOUT" \
                --max-time "$DOWNLOAD_TIMEOUT" \
                --output "$tmp_file" \
                "$effective_url"; then
                if [[ -s "$tmp_file" ]]; then
                    if mv -f "$tmp_file" "$out_file"; then
                        rc=0
                        break
                    fi
                    rc=1
                fi
            else
                rc=$?
            fi
            rm -f "$tmp_file"
            if ((i < attempts && delay > 0)); then
                sleep "$delay"
            fi
        done
        exit "$rc"
    )
}

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
        global-ms10 | global | ms10 | tier-global-ms10 | global-ms10-auto | global-auto | ms10-auto | tier-global-ms10-auto)
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
        ru-auto | russia-auto | rf-auto | tier-ru-auto | global-ms10-auto | global-auto | ms10-auto | tier-global-ms10-auto)
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
        tier_global_ms10) echo 10 ;;
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
        tier_global_ms10) echo "global-ms10" ;;
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

print_usage() {
    cat << 'USAGE'
Usage: xray-reality.sh <command> [options]

Commands:
  install                        Install Network Stealth Core (auto для РФ)
  add-clients [N]                Add N configs to existing setup (tier-aware limit)
  add-keys [N]                   Alias of add-clients [N]
  update                         Update Xray-core
  repair                         Re-apply units/firewall/monitoring and recover artifacts
  status                         Show current configuration and status
  logs [xray|health|all]         View service logs (default: all)
  diagnose                       Collect diagnostics
  rollback [dir]                 Roll back to backup
  uninstall                      Full removal (ports, configs, user, all)
  check-update                   Check for available updates

Options:
  --config <file>                Load config file (key=value)
  --dry-run                      Show actions without executing
  --verbose                      More logging (also: detailed status)
  --yes, --non-interactive       Skip prompts (automation mode)
  --num-configs <N>              Number of configs (tier-aware limit)
  --domain-profile <ru|ru-auto|global-ms10|global-ms10-auto|custom>
                                 Domain profile for install/add (default: ru)
  --start-port <1-65535>         Starting port (default: 443)
  --transport <grpc|http2>       Transport mode (default: grpc)
  --progress-mode <mode>         Progress output: auto|bar|plain|none
  --require-minisign             Fail when minisign is unavailable or signature is missing
  --allow-no-systemd             Allow install/update/repair without systemd (compat mode)
  --server-ip <ipv4>             Set server IPv4
  --server-ip6 <ipv6>            Set server IPv6
  --primary-domain-mode <mode>   First domain mode: adaptive|pinned
  --primary-pin-domain <domain>  Pinned first domain when mode=pinned
  --primary-adaptive-top-n <N>   Top-N candidate pool for adaptive mode
  --domain-check-parallelism <N> Max parallel domain probes during install check
  --domain-quarantine-fail-streak <N>
                                 Quarantine threshold by fail streak
  --domain-quarantine-cooldown-min <minutes>
                                 Quarantine cooldown window
  --xray-version <ver>           Override Xray version
  --help                         Show this help

Environment variables:
  XRAY_DOMAIN_PROFILE            Domain profile (ru|ru-auto|global-ms10|global-ms10-auto|custom)
  TRANSPORT                      Transport mode (grpc|http2, default: grpc)
  SHORT_ID_BYTES_MIN             Min Reality ShortID bytes (default: 8)
  SHORT_ID_BYTES_MAX             Max Reality ShortID bytes (default: 8)
  DOMAIN_HEALTH_RANKING          Use adaptive domain ranking (default: true)
  DOMAIN_HEALTH_PROBE_TIMEOUT    Domain probe timeout in health monitor (default: 2)
  DOMAIN_HEALTH_RATE_LIMIT_MS    Min delay between domain probes in health monitor (default: 250)
  DOMAIN_HEALTH_MAX_PROBES       Max domains probed per health cycle (default: 20)
  DOMAIN_HEALTH_FILE             Domain health score file path
  DOMAIN_CHECK_PARALLELISM       Parallel domain checks during install (default: 16)
  DOMAIN_QUARANTINE_FAIL_STREAK  Quarantine threshold by fail streak (default: 4)
  DOMAIN_QUARANTINE_COOLDOWN_MIN Quarantine cooldown in minutes (default: 120)
  PRIMARY_DOMAIN_MODE            First config domain mode: adaptive|pinned (default: adaptive)
  PRIMARY_PIN_DOMAIN             First config domain in pinned mode (default: first domain from tiers)
  PRIMARY_ADAPTIVE_TOP_N         Top-N candidates used in adaptive mode (default: 5)
  PROGRESS_MODE                  Progress output mode: auto|bar|plain|none (default: auto)
  DOWNLOAD_HOST_ALLOWLIST        Allowlist for critical download hosts (comma-separated)
  GH_PROXY_BASE                  Optional proxy base for github release mirrors
  ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP
                                  Allow minisign bootstrap download (default: false)
  REQUIRE_MINISIGN               Require minisign on install/update/repair (default: false)
  ALLOW_NO_SYSTEMD               Allow install/update/repair without systemd (default: false)
  GEO_VERIFY_HASH                Verify GeoIP/GeoSite SHA256 in updater (default: true)
  GEO_VERIFY_STRICT              Fail update when checksum file is unavailable (default: false)
  HEALTH_CHECK_INTERVAL          Health timer interval in seconds (default: 120)
  LOG_RETENTION_DAYS             Health log retention (default: 30)
  LOG_MAX_SIZE_MB                Max health log size in MB (default: 10)
USAGE
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
            echo "  6. Сборка конфигурации (${TRANSPORT} + Reality)"
            echo "  7. Создание systemd-сервиса + файрвол"
            echo "  8. Настройка health-мониторинга + auto-update"
            echo "  9. Генерация клиентских конфигов + QR-коды"
            echo "  10. Экспорт ClashMeta/SingBox"
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

load_config_file() {
    local file="$1"
    if [[ -z "$file" ]]; then
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        log WARN "Конфиг не найден: $file"
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
            XRAY_DOMAIN_TIER | XRAY_DOMAIN_PROFILE | XRAY_NUM_CONFIGS | XRAY_SPIDER_MODE | XRAY_START_PORT | XRAY_PROGRESS_MODE | DOMAIN_PROFILE | DOMAIN_TIER | NUM_CONFIGS | SPIDER_MODE | START_PORT | PROGRESS_MODE | XRAY_TRANSPORT | TRANSPORT | MUX_MODE | MUX_CONCURRENCY_MIN | MUX_CONCURRENCY_MAX | GRPC_IDLE_TIMEOUT_MIN | GRPC_IDLE_TIMEOUT_MAX | GRPC_HEALTH_TIMEOUT_MIN | GRPC_HEALTH_TIMEOUT_MAX | TCP_KEEPALIVE_MIN | TCP_KEEPALIVE_MAX | SHORT_ID_BYTES_MIN | SHORT_ID_BYTES_MAX | KEEP_LOCAL_BACKUPS | MAX_BACKUPS | REUSE_EXISTING | AUTO_ROLLBACK | XRAY_VERSION | XRAY_MIRRORS | MINISIGN_MIRRORS | QR_ENABLED | AUTO_UPDATE | AUTO_UPDATE_ONCALENDAR | AUTO_UPDATE_RANDOM_DELAY | ALLOW_INSECURE_SHA256 | ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP | REQUIRE_MINISIGN | ALLOW_NO_SYSTEMD | GEO_VERIFY_HASH | GEO_VERIFY_STRICT | XRAY_CUSTOM_DOMAINS | XRAY_DOMAINS_FILE | XRAY_SNI_POOLS_FILE | XRAY_GRPC_SERVICES_FILE | XRAY_TIERS_FILE | XRAY_DATA_DIR | XRAY_GEO_DIR | XRAY_SCRIPT_PATH | XRAY_UPDATE_SCRIPT | DOMAIN_CHECK | DOMAIN_CHECK_TIMEOUT | DOMAIN_CHECK_PARALLELISM | REALITY_TEST_PORTS | SKIP_REALITY_CHECK | DOMAIN_HEALTH_FILE | DOMAIN_HEALTH_PROBE_TIMEOUT | DOMAIN_HEALTH_RATE_LIMIT_MS | DOMAIN_HEALTH_MAX_PROBES | DOMAIN_HEALTH_RANKING | DOMAIN_QUARANTINE_FAIL_STREAK | DOMAIN_QUARANTINE_COOLDOWN_MIN | PRIMARY_DOMAIN_MODE | PRIMARY_PIN_DOMAIN | PRIMARY_ADAPTIVE_TOP_N | DOWNLOAD_HOST_ALLOWLIST | GH_PROXY_BASE | DOWNLOAD_TIMEOUT | DOWNLOAD_RETRIES | DOWNLOAD_RETRY_DELAY | SERVER_IP | SERVER_IP6 | DRY_RUN | VERBOSE | HEALTH_CHECK_INTERVAL | LOG_RETENTION_DAYS | LOG_MAX_SIZE_MB | HEALTH_LOG)
                printf -v "$key" '%s' "$value"
                ;;
            *) ;;
        esac
    done < "$file"
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
    local path_lc="${1,,}"
    [[ "$path_lc" =~ (^|/)[^/]*(xray|reality|network-stealth-core)[^/]*(/|$) ]]
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

validate_destructive_path_scope() {
    local name="$1"
    local path="$2"
    local resolved
    local base

    resolved=$(realpath -m "$path" 2> /dev/null || echo "$path")

    case "$name" in
        XRAY_KEYS | XRAY_BACKUP | XRAY_LOGS | XRAY_HOME | XRAY_DATA_DIR)
            if is_sensitive_system_path_prefix "$resolved" && ! path_has_project_scope_marker "$resolved"; then
                log ERROR "${name} в системном каталоге должен указывать на отдельный путь проекта (ожидается сегмент с xray/reality): ${resolved}"
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
                log ERROR "XRAY_GEO_DIR в системном каталоге должен указывать на путь проекта (xray/reality) или dirname(XRAY_BIN) (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_BIN)
            base=$(basename "$resolved")
            if [[ "$base" != "xray" ]]; then
                log ERROR "XRAY_BIN должен указывать на бинарник xray (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_SCRIPT_PATH)
            base=$(basename "$resolved")
            if [[ "$base" != "xray-reality.sh" ]]; then
                log ERROR "XRAY_SCRIPT_PATH должен указывать на xray-reality.sh (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_UPDATE_SCRIPT)
            base=$(basename "$resolved")
            if [[ "$base" != "xray-reality-update.sh" ]]; then
                log ERROR "XRAY_UPDATE_SCRIPT должен указывать на xray-reality-update.sh (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_CONFIG)
            base=$(basename "$resolved")
            if [[ "$base" != "config.json" ]]; then
                log ERROR "XRAY_CONFIG должен указывать на config.json (получено: ${resolved})"
                return 1
            fi
            ;;
        XRAY_ENV)
            base=$(basename "$resolved")
            if [[ "$base" != "config.env" ]]; then
                log ERROR "XRAY_ENV должен указывать на config.env (получено: ${resolved})"
                return 1
            fi
            ;;
        MINISIGN_KEY)
            base=$(basename "$resolved")
            if [[ "$base" != "minisign.pub" ]]; then
                log ERROR "MINISIGN_KEY должен указывать на minisign.pub (получено: ${resolved})"
                return 1
            fi
            ;;
        *) ;;
    esac

    if is_sensitive_system_path_prefix "$resolved" && ! path_has_project_scope_marker "$resolved"; then
        log ERROR "${name} в системном каталоге должен указывать на путь проекта (ожидается сегмент с xray/reality): ${resolved}"
        return 1
    fi

    return 0
}

validate_destructive_runtime_paths() {
    local var value dir
    local -a destructive_dirs=(
        XRAY_KEYS XRAY_BACKUP XRAY_LOGS XRAY_HOME XRAY_DATA_DIR XRAY_GEO_DIR
    )
    local -a destructive_files=(
        XRAY_BIN XRAY_CONFIG XRAY_ENV XRAY_SCRIPT_PATH XRAY_UPDATE_SCRIPT MINISIGN_KEY
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

strict_validate_runtime_inputs() {
    local action="${1:-$ACTION}"
    local var
    local -a safe_vars=(
        XRAY_BIN XRAY_CONFIG XRAY_ENV XRAY_KEYS XRAY_BACKUP XRAY_LOGS XRAY_HOME
        XRAY_DATA_DIR XRAY_GEO_DIR XRAY_SCRIPT_PATH XRAY_UPDATE_SCRIPT MINISIGN_KEY
        XRAY_CONFIG_FILE DOWNLOAD_HOST_ALLOWLIST XRAY_MIRRORS MINISIGN_MIRRORS
        GH_PROXY_BASE
        XRAY_GEOIP_URL XRAY_GEOSITE_URL XRAY_GEOIP_SHA256_URL XRAY_GEOSITE_SHA256_URL
        DOMAIN_HEALTH_FILE HEALTH_LOG
        AUTO_UPDATE_ONCALENDAR AUTO_UPDATE_RANDOM_DELAY
        HEALTH_CHECK_INTERVAL LOG_RETENTION_DAYS LOG_MAX_SIZE_MB
        PROGRESS_MODE XRAY_PROGRESS_MODE
    )

    for var in "${safe_vars[@]}"; do
        validate_no_control_chars "$var" "${!var:-}" || return 1
    done

    case "$action" in
        install | add-clients | add-keys | update | repair | diagnose | rollback | uninstall)
            validate_destructive_runtime_paths || return 1
            ;;
        *) ;;
    esac

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

    local url_var
    for url_var in XRAY_GEOIP_URL XRAY_GEOSITE_URL XRAY_GEOIP_SHA256_URL XRAY_GEOSITE_SHA256_URL; do
        if [[ -n "${!url_var:-}" ]] && ! is_valid_https_url "${!url_var}"; then
            log ERROR "${url_var}: требуется HTTPS URL"
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

    if [[ -n "${SERVER_IP:-}" ]] && ! is_valid_ipv4 "$SERVER_IP"; then
        log ERROR "Некорректный SERVER_IP: ${SERVER_IP}"
        return 1
    fi
    if [[ -n "${SERVER_IP6:-}" ]] && ! is_valid_ipv6 "$SERVER_IP6"; then
        log ERROR "Некорректный SERVER_IP6: ${SERVER_IP6}"
        return 1
    fi

    strict_validate_runtime_schedule_settings || return 1
    strict_validate_progress_mode || return 1
    strict_validate_runtime_common_ranges || return 1

    local port
    while read -r port; do
        port=$(trim_ws "$port")
        [[ -z "$port" ]] && continue
        if ! is_valid_port "$port"; then
            log ERROR "REALITY_TEST_PORTS содержит невалидный порт: ${port}"
            return 1
        fi
    done < <(split_list "$REALITY_TEST_PORTS")

    if [[ -n "$XRAY_VERSION" ]]; then
        if [[ "${XRAY_VERSION,,}" != "latest" ]]; then
            if [[ ! "$XRAY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$ ]]; then
                log ERROR "Некорректный XRAY_VERSION: ${XRAY_VERSION}"
                return 1
            fi
        fi
    fi
    if [[ -n "${XRAY_DOMAIN_PROFILE:-}" ]] && ! normalize_domain_tier "$XRAY_DOMAIN_PROFILE" > /dev/null 2>&1; then
        log ERROR "Некорректный XRAY_DOMAIN_PROFILE: ${XRAY_DOMAIN_PROFILE} (ожидается ru|ru-auto|global-ms10|global-ms10-auto|custom)"
        return 1
    fi
    if [[ -n "${XRAY_DOMAIN_TIER:-}" ]] && ! normalize_domain_tier "$XRAY_DOMAIN_TIER" > /dev/null 2>&1; then
        log ERROR "Некорректный XRAY_DOMAIN_TIER: ${XRAY_DOMAIN_TIER}"
        return 1
    fi
    strict_validate_primary_domain_controls || return 1

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

    case "$action" in
        install | add-clients | add-keys)
            validate_install_config || return 1
            ;;
        *) ;;
    esac

    return 0
}

validate_install_config() {
    local normalized_tier
    if ! normalized_tier=$(normalize_domain_tier "$DOMAIN_TIER"); then
        log WARN "Неверный DOMAIN_TIER: $DOMAIN_TIER — используем tier_ru"
        normalized_tier="tier_ru"
    fi
    DOMAIN_TIER="$normalized_tier"
    case "$TRANSPORT" in
        grpc | http2) ;;
        *)
            log WARN "Неверный TRANSPORT: $TRANSPORT (используем grpc)"
            TRANSPORT="grpc"
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
            log WARN "Неверный MUX_MODE: $MUX_MODE (используем on)"
            MUX_MODE="on"
            ;;
    esac
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
        install | update | repair | add-clients | add-keys) ;;
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
            install_flow
            ;;
        add-clients)
            strict_validate_runtime_inputs "add-clients"
            require_root
            require_systemd_runtime_for_action "add-clients"
            add_clients_flow
            ;;
        add-keys)
            strict_validate_runtime_inputs "add-keys"
            require_root
            require_systemd_runtime_for_action "add-keys"
            add_clients_flow
            ;;
        update)
            strict_validate_runtime_inputs "update"
            require_root
            require_systemd_runtime_for_action "update"
            update_flow
            ;;
        repair)
            strict_validate_runtime_inputs "repair"
            require_root
            require_systemd_runtime_for_action "repair"
            repair_flow
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
