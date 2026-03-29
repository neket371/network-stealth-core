#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

load_domain_list() {
    local list="$1"
    local item
    [[ -n "$list" ]] || return 0
    while read -r item; do
        item=$(trim_ws "$item")
        [[ -z "$item" ]] && continue
        printf '%s\n' "$item"
    done < <(split_list "$list")
}

normalize_catalog_text() {
    local value="${1:-}"
    value="${value//$'\r'/}"
    trim_ws "$value"
}

load_domains_from_file() {
    local file="$1"
    local -a result=()
    if [[ -n "$file" && -f "$file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(trim_ws "$line")
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            result+=("$line")
        done < "$file"
    fi
    printf '%s\n' "${result[@]}"
}

load_tier_domains_from_file() {
    local file="$1"
    local tier="$2"
    local -a result=()
    local current=""
    local line
    [[ -n "$file" && -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(trim_ws "$line")
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == "["*"]" ]]; then
            current="${line#\[}"
            current="${current%\]}"
            continue
        fi
        if [[ "$current" == "$tier" ]]; then
            result+=("$line")
        fi
    done < "$file"
    printf '%s\n' "${result[@]}"
}

catalog_supports_tier() {
    local file="$1"
    local tier="$2"
    [[ -n "$file" && -f "$file" ]] || return 1
    command -v jq > /dev/null 2>&1 || return 1
    jq -e --arg tier "$tier" '.tiers[$tier] != null' "$file" > /dev/null 2>&1
}

derive_provider_family_from_domain() {
    local domain="${1:-}"
    local -a labels=()
    local label_count
    [[ -n "$domain" ]] || return 1

    IFS='.' read -r -a labels <<< "$domain"
    label_count=${#labels[@]}
    if ((label_count < 2)); then
        printf '%s\n' "$domain"
        return 0
    fi

    local suffix="${labels[$((label_count - 2))]}.${labels[$((label_count - 1))]}"
    case "$suffix" in
        gov.ru | edu.ru | org.ru | com.ru | net.ru)
            if ((label_count >= 3)); then
                printf '%s.%s.%s\n' "${labels[$((label_count - 3))]}" "${labels[$((label_count - 2))]}" "${labels[$((label_count - 1))]}"
                return 0
            fi
            ;;
        *) ;;
    esac

    printf '%s.%s\n' "${labels[$((label_count - 2))]}" "${labels[$((label_count - 1))]}"
}

load_tier_domains_from_catalog() {
    local file="$1"
    local tier="$2"
    [[ -n "$file" && -f "$file" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0

    local domain
    while IFS= read -r domain; do
        domain=$(normalize_catalog_text "$domain")
        [[ -n "$domain" ]] || continue
        printf '%s\n' "$domain"
    done < <(jq -r --arg tier "$tier" '.tiers[$tier][]?.domain // empty' "$file" 2> /dev/null)
}

load_priority_domains_from_catalog() {
    local file="$1"
    [[ -n "$file" && -f "$file" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0

    local domain
    while IFS= read -r domain; do
        domain=$(normalize_catalog_text "$domain")
        [[ -n "$domain" ]] || continue
        printf '%s\n' "$domain"
    done < <(jq -r '.tiers.priority[]? // empty' "$file" 2> /dev/null)
}

populate_domain_metadata_from_catalog() {
    local file="$1"
    local tier="$2"
    [[ -n "$file" && -f "$file" ]] || return 1
    command -v jq > /dev/null 2>&1 || return 1
    jq empty "$file" > /dev/null 2>&1 || return 1

    declare -gA DOMAIN_PROVIDER_FAMILIES=()
    declare -gA DOMAIN_REGIONS=()
    declare -gA DOMAIN_PRIORITY_MAP=()
    declare -gA DOMAIN_RISK_MAP=()
    declare -gA DOMAIN_PORT_HINTS=()
    declare -gA DOMAIN_SNI_POOL_OVERRIDES=()

    local entry_json domain provider_family region priority risk port_csv sni_pool_csv
    while IFS= read -r entry_json; do
        [[ -n "$entry_json" ]] || continue
        domain=$(jq -r '.domain // empty' <<< "$entry_json" 2> /dev/null || true)
        domain=$(normalize_catalog_text "$domain")
        [[ -n "$domain" ]] || continue

        provider_family=$(jq -r '.provider_family // empty' <<< "$entry_json" 2> /dev/null || true)
        provider_family=$(normalize_catalog_text "$provider_family")
        if [[ -z "$provider_family" || "$provider_family" == "null" ]]; then
            provider_family=$(derive_provider_family_from_domain "$domain")
        fi

        region=$(jq -r '.region // "ru"' <<< "$entry_json" 2> /dev/null || true)
        region=$(normalize_catalog_text "$region")
        priority=$(jq -r '.priority // 0' <<< "$entry_json" 2> /dev/null || echo 0)
        risk=$(jq -r '.risk // "normal"' <<< "$entry_json" 2> /dev/null || echo "normal")
        risk=$(normalize_catalog_text "$risk")
        port_csv=$(jq -r '(.ports // [443,8443]) | map(tostring) | join(",")' <<< "$entry_json" 2> /dev/null || echo "443,8443")
        port_csv=$(normalize_catalog_text "$port_csv")
        sni_pool_csv=$(jq -r '(.sni_pool // []) | join(" ")' <<< "$entry_json" 2> /dev/null || true)
        sni_pool_csv=$(normalize_catalog_text "$sni_pool_csv")

        DOMAIN_PROVIDER_FAMILIES["$domain"]="$provider_family"
        DOMAIN_REGIONS["$domain"]="$region"
        DOMAIN_PRIORITY_MAP["$domain"]="$priority"
        DOMAIN_RISK_MAP["$domain"]="$risk"
        DOMAIN_PORT_HINTS["$domain"]="$port_csv"
        if [[ -n "$sni_pool_csv" && "$sni_pool_csv" != "null" ]]; then
            DOMAIN_SNI_POOL_OVERRIDES["$domain"]="$sni_pool_csv"
        fi
    done < <(jq -c --arg tier "$tier" '.tiers[$tier][]? // empty' "$file" 2> /dev/null)

    return 0
}

seed_domain_metadata_from_list() {
    local domain
    for domain in "$@"; do
        [[ -n "$domain" ]] || continue
        if [[ -z "${DOMAIN_PROVIDER_FAMILIES[$domain]:-}" ]]; then
            DOMAIN_PROVIDER_FAMILIES["$domain"]="$(derive_provider_family_from_domain "$domain")"
        fi
        if [[ -z "${DOMAIN_REGIONS[$domain]:-}" ]]; then
            DOMAIN_REGIONS["$domain"]="custom"
        fi
        if [[ -z "${DOMAIN_PRIORITY_MAP[$domain]:-}" ]]; then
            DOMAIN_PRIORITY_MAP["$domain"]="0"
        fi
        if [[ -z "${DOMAIN_RISK_MAP[$domain]:-}" ]]; then
            DOMAIN_RISK_MAP["$domain"]="custom"
        fi
        if [[ -z "${DOMAIN_PORT_HINTS[$domain]:-}" ]]; then
            DOMAIN_PORT_HINTS["$domain"]="443,8443"
        fi
    done
}

domain_provider_family_for() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || return 1
    if [[ -n "${DOMAIN_PROVIDER_FAMILIES[$domain]:-}" ]]; then
        printf '%s\n' "${DOMAIN_PROVIDER_FAMILIES[$domain]}"
        return 0
    fi
    derive_provider_family_from_domain "$domain"
}

check_domain_alive() {
    local domain="$1"
    local timeout_sec="${DOMAIN_CHECK_TIMEOUT:-3}"

    if ! is_valid_domain "$domain"; then
        debug_file "Invalid domain rejected: $domain"
        return 1
    fi

    if command -v timeout > /dev/null 2>&1 && command -v openssl > /dev/null 2>&1; then
        local -a ports=()
        mapfile -t ports < <(split_list "$REALITY_TEST_PORTS")
        if [[ ${#ports[@]} -eq 0 ]]; then
            ports=(443 8443 2053 2083 2087)
        fi
        local port
        for port in "${ports[@]}"; do
            # shellcheck disable=SC2016 # Single quotes intentional - args passed via $1/$2
            if timeout "$timeout_sec" bash -c 'echo | openssl s_client -connect "$1:$2" -servername "$1" 2>/dev/null' _ "$domain" "$port" | grep -q "CONNECTED"; then
                return 0
            fi
        done
        return 1
    fi
    if command -v curl > /dev/null 2>&1; then
        if curl_fetch_text "https://${domain}" -I --connect-timeout "$timeout_sec" --max-time "$timeout_sec" > /dev/null 2>&1; then
            return 0
        fi
        return 1
    fi
    log WARN "Нет openssl/curl для проверки домена $domain; считаем недоступным"
    return 1
}

filter_alive_domains() {
    if [[ "$DOMAIN_CHECK" != "true" ]]; then
        return 0
    fi
    if [[ ${#AVAILABLE_DOMAINS[@]} -eq 0 ]]; then
        return 0
    fi

    local parallelism="${DOMAIN_CHECK_PARALLELISM:-16}"
    if [[ ! "$parallelism" =~ ^[0-9]+$ ]] || ((parallelism < 1)); then
        parallelism=16
    fi
    if ((parallelism > ${#AVAILABLE_DOMAINS[@]})); then
        parallelism=${#AVAILABLE_DOMAINS[@]}
    fi

    log INFO "Проверяем доступность ${#AVAILABLE_DOMAINS[@]} доменов (parallelism=${parallelism})..."

    local tmp_dir
    local _old_umask
    _old_umask=$(umask)
    umask 077
    tmp_dir=$(mktemp -d)
    umask "$_old_umask"
    # shellcheck disable=SC2317,SC2329
    cleanup_filter_alive_domains_tmpdir() {
        local sig="${1:-}"
        [[ -n "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"
        trap - RETURN INT TERM
        if [[ -n "$sig" ]]; then
            kill -s "$sig" "$$"
        fi
    }
    trap cleanup_filter_alive_domains_tmpdir RETURN
    trap 'cleanup_filter_alive_domains_tmpdir INT' INT
    trap 'cleanup_filter_alive_domains_tmpdir TERM' TERM
    local domain i
    local active=0
    local wait_n_supported=false
    if ((BASH_VERSINFO[0] > 4)) || ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)); then
        wait_n_supported=true
    fi
    local -a fallback_pids=()
    local fallback_wait_idx=0

    for i in "${!AVAILABLE_DOMAINS[@]}"; do
        domain="${AVAILABLE_DOMAINS[$i]}"
        (
            if check_domain_alive "$domain"; then
                printf '%s' "$domain" > "${tmp_dir}/${i}.ok"
            fi
        ) &
        fallback_pids+=($!)
        active=$((active + 1))

        if ((active >= parallelism)); then
            if [[ "$wait_n_supported" == "true" ]]; then
                wait -n 2> /dev/null || true
            else
                wait "${fallback_pids[$fallback_wait_idx]}" 2> /dev/null || true
                fallback_wait_idx=$((fallback_wait_idx + 1))
            fi
            active=$((active - 1))
        fi
    done

    if [[ "$wait_n_supported" == "true" ]]; then
        while ((active > 0)); do
            wait -n 2> /dev/null || true
            active=$((active - 1))
        done
    else
        while ((fallback_wait_idx < ${#fallback_pids[@]})); do
            wait "${fallback_pids[$fallback_wait_idx]}" 2> /dev/null || true
            fallback_wait_idx=$((fallback_wait_idx + 1))
        done
    fi

    local -a alive=()
    for i in "${!AVAILABLE_DOMAINS[@]}"; do
        if [[ -f "${tmp_dir}/${i}.ok" ]]; then
            alive+=("$(< "${tmp_dir}/${i}.ok")")
        else
            log WARN "Домен недоступен: ${AVAILABLE_DOMAINS[$i]}"
        fi
    done

    if [[ ${#alive[@]} -gt 0 ]]; then
        AVAILABLE_DOMAINS=("${alive[@]}")
        log INFO "Доступные домены после проверки: ${#AVAILABLE_DOMAINS[@]}"
    else
        log WARN "Проверка доменов не удалась; используем исходный список"
    fi
}

load_map_file() {
    local file="$1"
    local map_name="$2"
    [[ -n "$file" && -f "$file" ]] || return 0
    local line key value
    local line_no=0
    local invalid_value_found=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" != *"="* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ -n "$key" && "$key" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            if [[ "$value" =~ [^-a-zA-Z0-9._\ ] ]]; then
                log ERROR "Невалидное значение в map-файле ${file}:${line_no} (key=${key})"
                invalid_value_found=true
                continue
            fi
            printf -v "${map_name}[$key]" '%s' "$value"
        fi
    done < "$file"

    if [[ "$invalid_value_found" == true ]]; then
        return 1
    fi
    return 0
}
