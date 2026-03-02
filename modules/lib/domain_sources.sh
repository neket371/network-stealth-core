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
