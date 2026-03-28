#!/usr/bin/env bash
# shellcheck shell=bash

VERSION_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/version_contract.sh"
if [[ ! -f "$VERSION_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    VERSION_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/version_contract.sh"
fi
if [[ ! -f "$VERSION_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль version contract: $VERSION_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/version_contract.sh
source "$VERSION_CONTRACT_MODULE"

LEGACY_TRANSPORT_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/legacy_transport_contract.sh"
if [[ ! -f "$LEGACY_TRANSPORT_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    LEGACY_TRANSPORT_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/legacy_transport_contract.sh"
fi
if [[ ! -f "$LEGACY_TRANSPORT_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль legacy transport contract: $LEGACY_TRANSPORT_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/legacy_transport_contract.sh
source "$LEGACY_TRANSPORT_CONTRACT_MODULE"

: "${SCRIPT_DIR:=}"
: "${MODULE_DIR:=}"
: "${DEFAULT_DATA_DIR:=/usr/local/share/xray-reality}"

: "${SCRIPT_VERSION:=}"
: "${SCRIPT_NAME:=}"

: "${XRAY_USER:=xray}"
: "${XRAY_GROUP:=xray}"
: "${XRAY_HOME:=/var/lib/xray}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_GEO_DIR:=}"
: "${XRAY_CONFIG:=/etc/xray/config.json}"
: "${XRAY_ENV:=/etc/xray-reality/config.env}"
: "${XRAY_POLICY:=/etc/xray-reality/policy.json}"
: "${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:=/etc/xray-reality/custom-domains.txt}"
: "${XRAY_SOURCE_KIND:=}"
: "${XRAY_SOURCE_REF:=}"
: "${XRAY_SOURCE_COMMIT:=}"
: "${XRAY_KEYS:=/etc/xray/private/keys}"
: "${XRAY_BACKUP:=/var/backups/xray}"
: "${XRAY_LOGS:=/var/log/xray}"
: "${XRAY_DATA_DIR:=}"
: "${XRAY_ALLOW_CUSTOM_DATA_DIR:=false}"
: "${XRAY_TIERS_FILE:=}"
: "${XRAY_SNI_POOLS_FILE:=}"
: "${XRAY_TRANSPORT_ENDPOINTS_FILE:=}"
: "${XRAY_GRPC_SERVICES_FILE:=}"
: "${XRAY_DOMAIN_CATALOG_FILE:=}"
: "${XRAY_SCRIPT_PATH:=/usr/local/bin/xray-reality.sh}"
: "${XRAY_UPDATE_SCRIPT:=/usr/local/bin/xray-reality-update.sh}"
: "${XRAY_CONFIG_FILE:=}"
: "${XRAY_DOMAIN_PROFILE:=}"
: "${XRAY_DOMAIN_TIER:=}"
: "${XRAY_NUM_CONFIGS:=}"
: "${XRAY_START_PORT:=}"
: "${XRAY_SPIDER_MODE:=}"
: "${XRAY_TRANSPORT:=}"
: "${XRAY_ADVANCED:=}"
: "${XRAY_PROGRESS_MODE:=}"
: "${XRAY_DOMAINS_FILE:=}"
: "${XRAY_CUSTOM_DOMAINS:=}"
: "${XRAY_VERSION:=}"
: "${XRAY_MIRRORS:=}"
: "${XRAY_GEOIP_URL:=}"
: "${XRAY_GEOSITE_URL:=}"
: "${XRAY_GEOIP_SHA256_URL:=}"
: "${XRAY_GEOSITE_SHA256_URL:=}"

: "${MINISIGN_KEY:=/etc/xray/minisign.pub}"
: "${MINISIGN_MIRRORS:=}"

: "${PKG_TYPE:=}"
: "${PKG_MANAGER:=}"
: "${PKG_UPDATE:=}"
: "${PKG_INSTALL:=}"

: "${ACTION:=install}"
: "${NON_INTERACTIVE:=false}"
: "${ASSUME_YES:=false}"
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${LOG_CONTEXT:=}"
: "${LOGS_TARGET:=}"
: "${ADD_CLIENTS_COUNT:=}"
: "${INSTALL_LOG:=/var/log/xray-install.log}"
: "${UPDATE_LOG:=/var/log/xray-update.log}"
: "${DIAG_LOG:=/var/log/xray-diagnose.log}"
: "${HEALTH_LOG:=}"
: "${SELF_CHECK_STATE_FILE:=/var/lib/xray/self-check.json}"
: "${SELF_CHECK_HISTORY_FILE:=/var/lib/xray/self-check-history.ndjson}"
: "${MEASUREMENTS_DIR:=/var/lib/xray/measurements}"
: "${MEASUREMENTS_SUMMARY_FILE:=/var/lib/xray/measurements/latest-summary.json}"
: "${MEASUREMENTS_ROTATION_STATE_FILE:=$(dirname "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}")/rotation-state.json}"

: "${SERVER_IP:=}"
: "${SERVER_IP6:=}"

: "${MAX_BACKUPS:=10}"
: "${CONNECTION_TIMEOUT:=10}"
: "${DOWNLOAD_TIMEOUT:=60}"
: "${DOWNLOAD_RETRIES:=3}"
: "${DOWNLOAD_RETRY_DELAY:=2}"
: "${HEALTH_CHECK_INTERVAL:=120}"
: "${SELF_CHECK_ENABLED:=true}"
: "${SELF_CHECK_URLS:=https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204}"
: "${SELF_CHECK_TIMEOUT_SEC:=8}"
: "${LOG_RETENTION_DAYS:=30}"
: "${LOG_MAX_SIZE_MB:=10}"
: "${KEEP_LOCAL_BACKUPS:=true}"
: "${ALLOW_INSECURE_SHA256:=false}"
: "${ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP:=false}"
: "${REQUIRE_MINISIGN:=false}"
: "${ALLOW_NO_SYSTEMD:=false}"

: "${AUTO_UPDATE:=true}"
: "${AUTO_UPDATE_ONCALENDAR:=weekly}"
: "${AUTO_UPDATE_RANDOM_DELAY:=1h}"
: "${AUTO_ROLLBACK:=true}"

: "${TRANSPORT:=xhttp}" # normal v7 actions are xhttp-only; legacy grpc/http2 require migrate-stealth
: "${PROGRESS_MODE:=auto}"
: "${SHORT_ID_BYTES_MIN:=8}"
: "${SHORT_ID_BYTES_MAX:=8}"

: "${DOMAIN_TIER:=tier_ru}"
: "${NUM_CONFIGS:=5}"
: "${SPIDER_MODE:=true}"
: "${START_PORT:=443}"
: "${DOMAIN_CHECK:=true}"
: "${DOMAIN_CHECK_TIMEOUT:=3}"
: "${DOMAIN_CHECK_PARALLELISM:=16}"
: "${REALITY_TEST_PORTS:=443,8443}"
: "${SKIP_REALITY_CHECK:=false}"
: "${DOMAIN_HEALTH_FILE:=/var/lib/xray/domain-health.json}"
: "${DOMAIN_HEALTH_PROBE_TIMEOUT:=2}"
: "${DOMAIN_HEALTH_RANKING:=true}"
: "${DOMAIN_HEALTH_RATE_LIMIT_MS:=250}"
: "${DOMAIN_HEALTH_MAX_PROBES:=20}"
: "${DOMAIN_QUARANTINE_FAIL_STREAK:=4}"
: "${DOMAIN_QUARANTINE_COOLDOWN_MIN:=120}"
: "${PRIMARY_DOMAIN_MODE:=adaptive}"
: "${PRIMARY_PIN_DOMAIN:=}"
: "${PRIMARY_ADAPTIVE_TOP_N:=5}"
: "${XRAY_DIRECT_FLOW:=xtls-rprx-vision}"
: "${BROWSER_DIALER_ENV_NAME:=xray.browser.dialer}"
: "${XRAY_BROWSER_DIALER_ADDRESS:=}"
: "${DOWNLOAD_HOST_ALLOWLIST:=}"
: "${GH_PROXY_BASE:=}"
: "${QR_ENABLED:=auto}"
: "${GEO_VERIFY_HASH:=true}"
: "${GEO_VERIFY_STRICT:=false}"
: "${REUSE_EXISTING:=true}"
: "${REUSE_EXISTING_CONFIG:=false}"
: "${HAS_IPV6:=false}"
: "${ROLLBACK_DIR:=}"
: "${ADVANCED_MODE:=false}"
: "${REPLAN:=false}"
: "${SYSTEMD_MANAGEMENT_DISABLED:=false}"

: "${ID:=}"
: "${VERSION_ID:=}"
: "${PRETTY_NAME:=}"

: "${RED:=}"
: "${GREEN:=}"
: "${YELLOW:=}"
: "${BLUE:=}"
: "${CYAN:=}"
: "${DIM:=}"
: "${BOLD:=}"
: "${NC:=}"
: "${UI_BOX_H:=-}"
: "${UI_BOX_V:=|}"

if ! declare -p PORTS > /dev/null 2>&1; then PORTS=(); fi
if ! declare -p PORTS_V6 > /dev/null 2>&1; then PORTS_V6=(); fi
if ! declare -p PRIVATE_KEYS > /dev/null 2>&1; then PRIVATE_KEYS=(); fi
if ! declare -p PUBLIC_KEYS > /dev/null 2>&1; then PUBLIC_KEYS=(); fi
if ! declare -p UUIDS > /dev/null 2>&1; then UUIDS=(); fi
if ! declare -p SHORT_IDS > /dev/null 2>&1; then SHORT_IDS=(); fi
if ! declare -p CONFIG_DOMAINS > /dev/null 2>&1; then CONFIG_DOMAINS=(); fi
if ! declare -p CONFIG_SNIS > /dev/null 2>&1; then CONFIG_SNIS=(); fi
if ! declare -p CONFIG_TRANSPORT_ENDPOINTS > /dev/null 2>&1; then CONFIG_TRANSPORT_ENDPOINTS=(); fi
if ! declare -p CONFIG_DESTS > /dev/null 2>&1; then CONFIG_DESTS=(); fi
if ! declare -p CONFIG_FPS > /dev/null 2>&1; then CONFIG_FPS=(); fi
if ! declare -p CONFIG_PROVIDER_FAMILIES > /dev/null 2>&1; then CONFIG_PROVIDER_FAMILIES=(); fi
if ! declare -p CONFIG_VLESS_ENCRYPTIONS > /dev/null 2>&1; then CONFIG_VLESS_ENCRYPTIONS=(); fi
if ! declare -p CONFIG_VLESS_DECRYPTIONS > /dev/null 2>&1; then CONFIG_VLESS_DECRYPTIONS=(); fi
if ! declare -p AVAILABLE_DOMAINS > /dev/null 2>&1; then AVAILABLE_DOMAINS=(); fi
if ! declare -p DOMAIN_PROVIDER_FAMILIES > /dev/null 2>&1; then declare -A DOMAIN_PROVIDER_FAMILIES=(); fi
if ! declare -p DOMAIN_REGIONS > /dev/null 2>&1; then declare -A DOMAIN_REGIONS=(); fi
if ! declare -p DOMAIN_PRIORITY_MAP > /dev/null 2>&1; then declare -A DOMAIN_PRIORITY_MAP=(); fi
if ! declare -p DOMAIN_RISK_MAP > /dev/null 2>&1; then declare -A DOMAIN_RISK_MAP=(); fi
if ! declare -p DOMAIN_PORT_HINTS > /dev/null 2>&1; then declare -A DOMAIN_PORT_HINTS=(); fi
if ! declare -p DOMAIN_SNI_POOL_OVERRIDES > /dev/null 2>&1; then declare -A DOMAIN_SNI_POOL_OVERRIDES=(); fi

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

sync_measurements_rotation_state_file_contract() {
    local previous_summary_file="${1:-${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}}"
    local current_summary_file="${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
    local previous_default_path current_default_path

    previous_default_path="$(dirname "$previous_summary_file")/rotation-state.json"
    current_default_path="$(dirname "$current_summary_file")/rotation-state.json"

    if [[ -z "${MEASUREMENTS_ROTATION_STATE_FILE:-}" || "$MEASUREMENTS_ROTATION_STATE_FILE" == "$previous_default_path" ]]; then
        MEASUREMENTS_ROTATION_STATE_FILE="$current_default_path"
    fi
}
if ! declare -p FIREWALL_ROLLBACK_ENTRIES > /dev/null 2>&1; then FIREWALL_ROLLBACK_ENTRIES=(); fi
if ! declare -p FIREWALL_FIREWALLD_DIRTY > /dev/null 2>&1; then FIREWALL_FIREWALLD_DIRTY=false; fi
if ! declare -p CREATED_PATHS > /dev/null 2>&1; then CREATED_PATHS=(); fi
if ! declare -p CREATED_PATH_SET > /dev/null 2>&1; then declare -A CREATED_PATH_SET=(); fi
if ! declare -p BACKUP_STACK > /dev/null 2>&1; then BACKUP_STACK=(); fi
if ! declare -p LOCAL_BACKUP_MAP > /dev/null 2>&1; then declare -A LOCAL_BACKUP_MAP=(); fi
: "${BACKUP_SESSION_DIR:=}"
