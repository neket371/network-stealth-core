#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

policy_urls_json() {
    local raw_urls="${SELF_CHECK_URLS:-}"
    if declare -F split_list > /dev/null 2>&1; then
        split_list "$raw_urls" | jq -R . | jq -s .
        return 0
    fi
    printf '%s\n' "$raw_urls" | tr ', ' '\n' | sed '/^$/d' | jq -R . | jq -s .
}

policy_write_file() {
    local file="$1"
    local content="$2"
    local dir tmp
    dir=$(dirname "$file")
    mkdir -p "$dir"
    if declare -F backup_file > /dev/null 2>&1; then
        backup_file "$file"
    fi
    tmp=$(mktemp "${file}.tmp.XXXXXX")
    printf '%s\n' "$content" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
    chown root:root "$file" 2> /dev/null || true
}

policy_json_from_runtime() {
    local domain_profile="${DOMAIN_PROFILE:-${DOMAIN_TIER:-tier_ru}}"
    local measurement_variants='["recommended","rescue","emergency"]'
    local probe_urls_json='[]'
    probe_urls_json=$(policy_urls_json 2> /dev/null || printf '[]')

    jq -n \
        --arg generated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg contract "${STEALTH_CONTRACT_VERSION}" \
        --arg transport "${TRANSPORT:-xhttp}" \
        --arg flow "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}" \
        --arg xray_min_version "${XRAY_CLIENT_MIN_VERSION}" \
        --arg tier "${DOMAIN_TIER:-tier_ru}" \
        --arg domain_profile "$domain_profile" \
        --argjson num_configs "${NUM_CONFIGS:-0}" \
        --arg primary_mode "${PRIMARY_DOMAIN_MODE:-adaptive}" \
        --arg primary_pin "${PRIMARY_PIN_DOMAIN:-}" \
        --argjson adaptive_top_n "${PRIMARY_ADAPTIVE_TOP_N:-5}" \
        --arg self_check_enabled "${SELF_CHECK_ENABLED:-true}" \
        --argjson self_check_timeout "${SELF_CHECK_TIMEOUT_SEC:-8}" \
        --arg self_check_state "${SELF_CHECK_STATE_FILE:-/var/lib/xray/self-check.json}" \
        --arg self_check_history "${SELF_CHECK_HISTORY_FILE:-/var/lib/xray/self-check-history.ndjson}" \
        --arg measurements_dir "${MEASUREMENTS_DIR:-/var/lib/xray/measurements}" \
        --arg measurements_summary "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}" \
        --arg measurements_rotation_state "${MEASUREMENTS_ROTATION_STATE_FILE:-$(dirname "${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}")/rotation-state.json}" \
        --arg browser_dialer_env "${BROWSER_DIALER_ENV_NAME:-xray.browser.dialer}" \
        --arg browser_dialer_address "${XRAY_BROWSER_DIALER_ADDRESS:-127.0.0.1:11050}" \
        --argjson probe_urls "$probe_urls_json" \
        --argjson measurement_variants "$measurement_variants" \
        --arg auto_update "${AUTO_UPDATE:-true}" \
        --arg auto_update_oncalendar "${AUTO_UPDATE_ONCALENDAR:-weekly}" \
        --arg auto_update_random_delay "${AUTO_UPDATE_RANDOM_DELAY:-1h}" \
        --arg download_host_allowlist "${DOWNLOAD_HOST_ALLOWLIST:-github.com,api.github.com,objects.githubusercontent.com,raw.githubusercontent.com,release-assets.githubusercontent.com,ghproxy.com}" \
        --arg geo_verify_hash "${GEO_VERIFY_HASH:-true}" \
        --arg geo_verify_strict "${GEO_VERIFY_STRICT:-false}" \
        --arg geoip_url "${XRAY_GEOIP_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat}" \
        --arg geosite_url "${XRAY_GEOSITE_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat}" \
        --arg geoip_sha256_url "${XRAY_GEOIP_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum}" \
        --arg geosite_sha256_url "${XRAY_GEOSITE_SHA256_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum}" \
        --arg replan "${REPLAN:-false}" \
        '{
            schema_version: 1,
            generated: $generated,
            stealth_contract_version: $contract,
            transport: {
                name: $transport,
                flow: $flow,
                vless_encryption: true,
                browser_dialer_env: $browser_dialer_env,
                browser_dialer_address: $browser_dialer_address,
                xray_min_version: $xray_min_version
            },
            domain: {
                profile: $domain_profile,
                tier: $tier,
                num_configs: $num_configs,
                primary_mode: $primary_mode,
                primary_pin_domain: (if ($primary_pin | length) > 0 then $primary_pin else null end),
                adaptive_top_n: $adaptive_top_n
            },
            self_check: {
                enabled: ($self_check_enabled == "true"),
                timeout_sec: $self_check_timeout,
                urls: $probe_urls,
                state_file: $self_check_state,
                history_file: $self_check_history
            },
            measurement: {
                variants: $measurement_variants,
                reports_dir: $measurements_dir,
                summary_file: $measurements_summary,
                rotation_state_file: $measurements_rotation_state,
                urls: $probe_urls
            },
            update: {
                auto_update: ($auto_update == "true"),
                oncalendar: $auto_update_oncalendar,
                random_delay: $auto_update_random_delay,
                download_host_allowlist: $download_host_allowlist,
                geo_verify_hash: ($geo_verify_hash == "true"),
                geo_verify_strict: ($geo_verify_strict == "true"),
                geo_assets: {
                    geoip_url: $geoip_url,
                    geosite_url: $geosite_url,
                    geoip_sha256_url: $geoip_sha256_url,
                    geosite_sha256_url: $geosite_sha256_url
                },
                replan: ($replan == "true")
            }
        }'
}

save_policy_file() {
    local file="${1:-${XRAY_POLICY:-/etc/xray-reality/policy.json}}"
    local policy_json
    policy_json=$(policy_json_from_runtime) || return 1
    policy_write_file "$file" "$policy_json"
}

load_policy_file() {
    local file="$1"
    local previous_measurements_summary_file="${MEASUREMENTS_SUMMARY_FILE:-/var/lib/xray/measurements/latest-summary.json}"
    [[ -n "$file" && -f "$file" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0
    jq empty "$file" > /dev/null 2>&1 || return 0

    DOMAIN_TIER=$(jq -r '.domain.tier // empty' "$file" 2> /dev/null || printf '%s' "${DOMAIN_TIER:-}")
    if [[ -z "$DOMAIN_TIER" || "$DOMAIN_TIER" == "null" ]]; then
        DOMAIN_TIER="tier_ru"
    fi

    local loaded_domain_profile
    loaded_domain_profile=$(jq -r '.domain.profile // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_domain_profile" && "$loaded_domain_profile" != "null" ]]; then
        DOMAIN_PROFILE="$loaded_domain_profile"
    fi

    local loaded_num_configs
    loaded_num_configs=$(jq -r '.domain.num_configs // empty' "$file" 2> /dev/null || true)
    if [[ "$loaded_num_configs" =~ ^[0-9]+$ ]]; then
        NUM_CONFIGS="$loaded_num_configs"
    fi

    local loaded_primary_mode
    loaded_primary_mode=$(jq -r '.domain.primary_mode // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_primary_mode" && "$loaded_primary_mode" != "null" ]]; then
        PRIMARY_DOMAIN_MODE="$loaded_primary_mode"
    fi

    local loaded_primary_pin
    loaded_primary_pin=$(jq -r '.domain.primary_pin_domain // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_primary_pin" && "$loaded_primary_pin" != "null" ]]; then
        PRIMARY_PIN_DOMAIN="$loaded_primary_pin"
    fi

    local loaded_top_n
    loaded_top_n=$(jq -r '.domain.adaptive_top_n // empty' "$file" 2> /dev/null || true)
    if [[ "$loaded_top_n" =~ ^[0-9]+$ ]]; then
        PRIMARY_ADAPTIVE_TOP_N="$loaded_top_n"
    fi

    local loaded_transport
    loaded_transport=$(jq -r '.transport.name // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_transport" && "$loaded_transport" != "null" ]]; then
        TRANSPORT="$loaded_transport"
    fi

    local loaded_urls
    loaded_urls=$(jq -r '.self_check.urls // [] | join(",")' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_urls" && "$loaded_urls" != "null" ]]; then
        SELF_CHECK_URLS="$loaded_urls"
    fi

    local loaded_timeout
    loaded_timeout=$(jq -r '.self_check.timeout_sec // empty' "$file" 2> /dev/null || true)
    if [[ "$loaded_timeout" =~ ^[0-9]+$ ]]; then
        SELF_CHECK_TIMEOUT_SEC="$loaded_timeout"
    fi

    local loaded_reports_dir
    loaded_reports_dir=$(jq -r '.measurement.reports_dir // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_reports_dir" && "$loaded_reports_dir" != "null" ]]; then
        MEASUREMENTS_DIR="$loaded_reports_dir"
    fi

    local loaded_summary_file
    loaded_summary_file=$(jq -r '.measurement.summary_file // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_summary_file" && "$loaded_summary_file" != "null" ]]; then
        MEASUREMENTS_SUMMARY_FILE="$loaded_summary_file"
    fi

    local loaded_rotation_state_file
    loaded_rotation_state_file=$(jq -r '.measurement.rotation_state_file // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_rotation_state_file" && "$loaded_rotation_state_file" != "null" ]]; then
        MEASUREMENTS_ROTATION_STATE_FILE="$loaded_rotation_state_file"
    fi

    local loaded_download_host_allowlist
    loaded_download_host_allowlist=$(jq -r '.update.download_host_allowlist // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_download_host_allowlist" && "$loaded_download_host_allowlist" != "null" ]]; then
        DOWNLOAD_HOST_ALLOWLIST="$loaded_download_host_allowlist"
    fi

    local loaded_geo_verify_hash
    loaded_geo_verify_hash=$(jq -r 'if .update.geo_verify_hash == true then "true" elif .update.geo_verify_hash == false then "false" else empty end' "$file" 2> /dev/null || true)
    if [[ "$loaded_geo_verify_hash" == "true" || "$loaded_geo_verify_hash" == "false" ]]; then
        GEO_VERIFY_HASH="$loaded_geo_verify_hash"
    fi

    local loaded_geo_verify_strict
    loaded_geo_verify_strict=$(jq -r 'if .update.geo_verify_strict == true then "true" elif .update.geo_verify_strict == false then "false" else empty end' "$file" 2> /dev/null || true)
    if [[ "$loaded_geo_verify_strict" == "true" || "$loaded_geo_verify_strict" == "false" ]]; then
        GEO_VERIFY_STRICT="$loaded_geo_verify_strict"
    fi

    local loaded_geoip_url
    loaded_geoip_url=$(jq -r '.update.geo_assets.geoip_url // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_geoip_url" && "$loaded_geoip_url" != "null" ]]; then
        XRAY_GEOIP_URL="$loaded_geoip_url"
    fi

    local loaded_geosite_url
    loaded_geosite_url=$(jq -r '.update.geo_assets.geosite_url // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_geosite_url" && "$loaded_geosite_url" != "null" ]]; then
        XRAY_GEOSITE_URL="$loaded_geosite_url"
    fi

    local loaded_geoip_sha256_url
    loaded_geoip_sha256_url=$(jq -r '.update.geo_assets.geoip_sha256_url // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_geoip_sha256_url" && "$loaded_geoip_sha256_url" != "null" ]]; then
        XRAY_GEOIP_SHA256_URL="$loaded_geoip_sha256_url"
    fi

    local loaded_geosite_sha256_url
    loaded_geosite_sha256_url=$(jq -r '.update.geo_assets.geosite_sha256_url // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_geosite_sha256_url" && "$loaded_geosite_sha256_url" != "null" ]]; then
        XRAY_GEOSITE_SHA256_URL="$loaded_geosite_sha256_url"
    fi

    local loaded_flow
    loaded_flow=$(jq -r '.transport.flow // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_flow" && "$loaded_flow" != "null" ]]; then
        XRAY_DIRECT_FLOW="$loaded_flow"
    fi

    local loaded_browser_env
    loaded_browser_env=$(jq -r '.transport.browser_dialer_env // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_browser_env" && "$loaded_browser_env" != "null" ]]; then
        BROWSER_DIALER_ENV_NAME="$loaded_browser_env"
    fi

    local loaded_browser_addr
    loaded_browser_addr=$(jq -r '.transport.browser_dialer_address // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_browser_addr" && "$loaded_browser_addr" != "null" ]]; then
        XRAY_BROWSER_DIALER_ADDRESS="$loaded_browser_addr"
    fi

    local loaded_client_min_version
    loaded_client_min_version=$(jq -r '.transport.xray_min_version // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_client_min_version" && "$loaded_client_min_version" != "null" ]]; then
        XRAY_CLIENT_MIN_VERSION="$loaded_client_min_version"
    fi

    local loaded_contract_version
    loaded_contract_version=$(jq -r '.stealth_contract_version // empty' "$file" 2> /dev/null || true)
    if [[ -n "$loaded_contract_version" && "$loaded_contract_version" != "null" ]]; then
        STEALTH_CONTRACT_VERSION="$loaded_contract_version"
    fi

    local loaded_replan
    loaded_replan=$(jq -r '.update.replan // empty' "$file" 2> /dev/null || true)
    if [[ "$loaded_replan" == "true" || "$loaded_replan" == "false" ]]; then
        REPLAN="$loaded_replan"
    fi

    if declare -F sync_measurements_rotation_state_file_contract > /dev/null 2>&1; then
        sync_measurements_rotation_state_file_contract "$previous_measurements_summary_file"
    fi
}
