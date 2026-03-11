#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

setup_domains() {
    log STEP "Настраиваем домены (Spider Mode v2)..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Используем домены из текущей конфигурации"
        return 0
    fi

    local tiers_file="$XRAY_TIERS_FILE"
    if [[ -z "$tiers_file" || ! -f "$tiers_file" ]]; then
        log ERROR "Файл tiers не найден: $tiers_file"
        return 1
    fi

    local selected_tier
    selected_tier="${DOMAIN_TIER:-tier_ru}"
    if ! selected_tier=$(normalize_domain_tier "$selected_tier"); then
        selected_tier="tier_ru"
    fi
    DOMAIN_TIER="$selected_tier"

    declare -gA DOMAIN_PROVIDER_FAMILIES=()
    declare -gA DOMAIN_REGIONS=()
    declare -gA DOMAIN_PRIORITY_MAP=()
    declare -gA DOMAIN_RISK_MAP=()
    declare -gA DOMAIN_PORT_HINTS=()
    declare -gA DOMAIN_SNI_POOL_OVERRIDES=()

    local -a tier_domains=()
    if [[ "$selected_tier" != "custom" ]]; then
        if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "$selected_tier"; then
            mapfile -t tier_domains < <(load_tier_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "$selected_tier")
            populate_domain_metadata_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "$selected_tier" || true
        else
            mapfile -t tier_domains < <(load_tier_domains_from_file "$tiers_file" "$selected_tier")
        fi
        if [[ ${#tier_domains[@]} -eq 0 && "$selected_tier" != "tier_ru" ]]; then
            log WARN "Тир ${selected_tier} пустой; используем tier_ru"
            selected_tier="tier_ru"
            DOMAIN_TIER="tier_ru"
            if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "tier_ru"; then
                mapfile -t tier_domains < <(load_tier_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "tier_ru")
                populate_domain_metadata_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "tier_ru" || true
            else
                mapfile -t tier_domains < <(load_tier_domains_from_file "$tiers_file" "tier_ru")
            fi
        fi
    fi

    local -a custom_domains=()
    if [[ -n "$XRAY_CUSTOM_DOMAINS" ]]; then
        mapfile -t custom_domains < <(load_domain_list "$XRAY_CUSTOM_DOMAINS")
    elif [[ -n "$XRAY_DOMAINS_FILE" ]]; then
        mapfile -t custom_domains < <(load_domains_from_file "$XRAY_DOMAINS_FILE")
    fi

    if [[ ${#custom_domains[@]} -gt 0 ]]; then
        AVAILABLE_DOMAINS=("${custom_domains[@]}")
        DOMAIN_TIER="custom"
    else
        AVAILABLE_DOMAINS=("${tier_domains[@]}")
    fi
    seed_domain_metadata_from_list "${AVAILABLE_DOMAINS[@]}"

    if [[ ${#AVAILABLE_DOMAINS[@]} -eq 0 ]]; then
        log ERROR "Список доменов пуст. Проверьте XRAY_CUSTOM_DOMAINS/XRAY_DOMAINS_FILE."
        return 1
    fi

    filter_alive_domains
    rank_domains_by_health
    filter_quarantined_domains

    if [[ "${SPIDER_MODE:-false}" == true ]] && [[ ${#AVAILABLE_DOMAINS[@]} -gt 0 ]] && [[ $NUM_CONFIGS -gt ${#AVAILABLE_DOMAINS[@]} ]]; then
        log WARN "Spider Mode: конфигов больше, чем доменов; домены будут повторяться"
    fi

    declare -gA SNI_POOLS=()
    declare -gA TRANSPORT_ENDPOINT_SEEDS=()
    if [[ -n "$XRAY_SNI_POOLS_FILE" && -f "$XRAY_SNI_POOLS_FILE" ]]; then
        load_map_file "$XRAY_SNI_POOLS_FILE" SNI_POOLS || return 1
    else
        log WARN "SNI pools file не найден: $XRAY_SNI_POOLS_FILE"
    fi
    local sni_domain
    for sni_domain in "${!DOMAIN_SNI_POOL_OVERRIDES[@]}"; do
        SNI_POOLS["$sni_domain"]="${DOMAIN_SNI_POOL_OVERRIDES[$sni_domain]}"
    done
    if transport_is_legacy "$TRANSPORT"; then
        if [[ -n "$XRAY_TRANSPORT_ENDPOINTS_FILE" && -f "$XRAY_TRANSPORT_ENDPOINTS_FILE" ]]; then
            load_map_file "$XRAY_TRANSPORT_ENDPOINTS_FILE" TRANSPORT_ENDPOINT_SEEDS || return 1
        else
            log WARN "Файл legacy transport endpoint seeds не найден: $XRAY_TRANSPORT_ENDPOINTS_FILE"
        fi
    fi
    validate_domain_map_coverage || return 1
    local tier_limit
    tier_limit=$(max_configs_for_tier "$DOMAIN_TIER")
    if [[ "$DOMAIN_TIER" == tier_* && ${#AVAILABLE_DOMAINS[@]} -lt tier_limit ]]; then
        log WARN "Для тира ${DOMAIN_TIER} рекомендовано >=${tier_limit} доменов (сейчас: ${#AVAILABLE_DOMAINS[@]})"
    fi

    log OK "Домены настроены (доступно: ${#AVAILABLE_DOMAINS[@]})"
}

rank_domains_by_health() {
    if [[ "$DOMAIN_HEALTH_RANKING" != "true" ]]; then
        return 0
    fi
    if [[ ${#AVAILABLE_DOMAINS[@]} -le 1 ]]; then
        return 0
    fi
    if [[ -z "$DOMAIN_HEALTH_FILE" || ! -f "$DOMAIN_HEALTH_FILE" ]]; then
        return 0
    fi
    if ! command -v jq > /dev/null 2>&1; then
        return 0
    fi
    if ! jq empty "$DOMAIN_HEALTH_FILE" > /dev/null 2>&1; then
        log WARN "Пропускаем DOMAIN_HEALTH_RANKING: невалидный JSON ${DOMAIN_HEALTH_FILE}"
        return 0
    fi

    local -a ranked=()
    local i domain score
    mapfile -t ranked < <(
        for i in "${!AVAILABLE_DOMAINS[@]}"; do
            domain="${AVAILABLE_DOMAINS[$i]}"
            score=$(jq -r --arg d "$domain" '.domains[$d].score // 0' "$DOMAIN_HEALTH_FILE" 2> /dev/null || echo 0)
            if [[ ! "$score" =~ ^-?[0-9]+$ ]]; then
                score=0
            fi
            printf '%s\t%06d\t%s\n' "$score" "$i" "$domain"
        done | sort -t$'\t' -k1,1nr -k2,2n | cut -f3-
    )

    if [[ ${#ranked[@]} -gt 0 ]]; then
        AVAILABLE_DOMAINS=("${ranked[@]}")
        log INFO "Доменный рейтинг применён (${DOMAIN_HEALTH_FILE})"
    fi
}

is_domain_quarantined_by_health() {
    local domain="$1"
    [[ -n "$domain" ]] || return 1
    [[ "$DOMAIN_HEALTH_RANKING" == "true" ]] || return 1
    [[ -n "$DOMAIN_HEALTH_FILE" && -f "$DOMAIN_HEALTH_FILE" ]] || return 1
    command -v jq > /dev/null 2>&1 || return 1

    local fail_streak
    fail_streak=$(jq -r --arg d "$domain" '.domains[$d].fail_streak // 0' "$DOMAIN_HEALTH_FILE" 2> /dev/null || echo 0)
    [[ "$fail_streak" =~ ^[0-9]+$ ]] || fail_streak=0
    if ((fail_streak < DOMAIN_QUARANTINE_FAIL_STREAK)); then
        return 1
    fi

    local last_fail
    last_fail=$(jq -r --arg d "$domain" '.domains[$d].last_fail // empty' "$DOMAIN_HEALTH_FILE" 2> /dev/null || true)
    [[ -n "$last_fail" ]] || return 1

    local now_epoch fail_epoch
    now_epoch=$(date +%s 2> /dev/null || echo 0)
    fail_epoch=$(date -d "$last_fail" +%s 2> /dev/null || echo 0)
    [[ "$now_epoch" =~ ^[0-9]+$ ]] || return 1
    [[ "$fail_epoch" =~ ^[0-9]+$ ]] || return 1
    ((now_epoch > 0 && fail_epoch > 0)) || return 1

    local cooldown_sec=$((DOMAIN_QUARANTINE_COOLDOWN_MIN * 60))
    ((cooldown_sec > 0)) || return 1
    if ((now_epoch - fail_epoch < cooldown_sec)); then
        return 0
    fi
    return 1
}

filter_quarantined_domains() {
    if [[ "$DOMAIN_HEALTH_RANKING" != "true" ]]; then
        return 0
    fi
    if [[ ${#AVAILABLE_DOMAINS[@]} -le 1 ]]; then
        return 0
    fi

    local -a kept=()
    local -a quarantined=()
    local domain
    for domain in "${AVAILABLE_DOMAINS[@]}"; do
        if is_domain_quarantined_by_health "$domain"; then
            quarantined+=("$domain")
        else
            kept+=("$domain")
        fi
    done

    if [[ ${#quarantined[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ ${#kept[@]} -eq 0 ]]; then
        log WARN "Все домены попали в quarantine; используем исходный список"
        return 0
    fi

    AVAILABLE_DOMAINS=("${kept[@]}")
    log WARN "Quarantine активен: исключено доменов ${#quarantined[@]} (cooldown ${DOMAIN_QUARANTINE_COOLDOWN_MIN}m)"
}

validate_domain_map_coverage() {
    local strict=false
    if [[ "$DOMAIN_TIER" == tier_* ]]; then
        strict=true
    fi

    local -a missing_sni=()
    local -a missing_grpc=()
    local domain
    for domain in "${AVAILABLE_DOMAINS[@]}"; do
        [[ -n "${SNI_POOLS[$domain]:-}" ]] || missing_sni+=("$domain")
        if transport_is_legacy "$TRANSPORT"; then
            [[ -n "${TRANSPORT_ENDPOINT_SEEDS[$domain]:-}" ]] || missing_grpc+=("$domain")
        fi
    done

    if [[ ${#missing_sni[@]} -eq 0 && ${#missing_grpc[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ ${#missing_sni[@]} -gt 0 ]]; then
        log WARN "Домены без SNI pool: ${missing_sni[*]}"
    fi
    if [[ ${#missing_grpc[@]} -gt 0 ]]; then
        log WARN "Домены без gRPC pool: ${missing_grpc[*]}"
    fi

    if [[ "$strict" == "true" ]]; then
        log ERROR "Неполное покрытие map-файлов для ${DOMAIN_TIER}. Исправьте sni_pools.map и transport_endpoints.map для legacy transport."
        return 1
    fi
}

load_priority_domains() {
    local -a priority=()
    if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "priority"; then
        mapfile -t priority < <(load_priority_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE")
    fi
    if [[ ${#priority[@]} -eq 0 ]] && [[ -n "${XRAY_DOMAIN_CATALOG_FILE:-}" && -f "${XRAY_DOMAIN_CATALOG_FILE:-}" ]] && command -v jq > /dev/null 2>&1; then
        mapfile -t priority < <(jq -r '
            [.tiers.tier_ru[]?, .tiers.tier_global_ms10[]?]
            | flatten
            | map(select((.priority // 0) > 0))
            | sort_by(-(.priority // 0), .domain)
            | .[].domain
        ' "$XRAY_DOMAIN_CATALOG_FILE" 2> /dev/null || true)
    fi
    if [[ -n "$XRAY_TIERS_FILE" && -f "$XRAY_TIERS_FILE" ]]; then
        if [[ ${#priority[@]} -eq 0 ]]; then
            mapfile -t priority < <(load_tier_domains_from_file "$XRAY_TIERS_FILE" "priority")
        fi
    fi
    printf '%s\n' "${priority[@]}"
}

shuffle_array_inplace() {
    local -n _arr="$1"
    local _len=${#_arr[@]}
    if ((_len <= 1)); then
        return 0
    fi
    local i j tmp
    for ((i = _len - 1; i > 0; i--)); do
        j=$(rand_between 0 "$i")
        tmp="${_arr[$i]}"
        _arr[i]="${_arr[j]}"
        _arr[j]="$tmp"
    done
}

domain_exists_in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

build_diverse_cycle_from_pool() {
    local pool_name="$1"
    local out_name="$2"
    local previous_domain="${3:-}"
    local previous_family=""
    if [[ -n "$previous_domain" ]]; then
        previous_family=$(domain_provider_family_for "$previous_domain" 2> /dev/null || true)
    fi

    # shellcheck disable=SC2034 # nameref writes caller variable.
    local -n _pool="$pool_name"
    # shellcheck disable=SC2034 # nameref writes caller variable.
    local -n _out="$out_name"

    local -A seen_families=()
    local -a preferred=()
    local -a deferred=()
    local domain family

    for domain in "${_pool[@]}"; do
        [[ -n "$domain" ]] || continue
        family=$(domain_provider_family_for "$domain" 2> /dev/null || true)
        if [[ -z "$family" ]]; then
            family="$domain"
        fi

        if [[ ${#preferred[@]} -eq 0 && -n "$previous_domain" && "$domain" == "$previous_domain" && ${#_pool[@]} -gt 1 ]]; then
            deferred+=("$domain")
            continue
        fi

        if [[ -z "${seen_families[$family]:-}" && ! (${#preferred[@]} -eq 0 && -n "$previous_family" && "$family" == "$previous_family" && ${#_pool[@]} -gt 1) ]]; then
            preferred+=("$domain")
            seen_families["$family"]=1
        else
            deferred+=("$domain")
        fi
    done

    _out=("${preferred[@]}" "${deferred[@]}")
}

select_primary_domain() {
    local mode="${PRIMARY_DOMAIN_MODE,,}"
    local pin_domain="$PRIMARY_PIN_DOMAIN"
    local -a priority_group=()
    local domain

    if [[ "$mode" == "pinned" ]]; then
        if domain_exists_in_array "$pin_domain" "${AVAILABLE_DOMAINS[@]}"; then
            printf '%s' "$pin_domain"
            return 0
        fi
        mapfile -t priority_group < <(load_priority_domains)
        for domain in "${priority_group[@]}"; do
            if domain_exists_in_array "$domain" "${AVAILABLE_DOMAINS[@]}"; then
                printf '%s' "$domain"
                return 0
            fi
        done
        printf '%s' "${AVAILABLE_DOMAINS[0]}"
        return 0
    fi

    mapfile -t priority_group < <(load_priority_domains)
    local -a candidates=()
    if [[ ${#priority_group[@]} -gt 0 ]]; then
        for domain in "${AVAILABLE_DOMAINS[@]}"; do
            if domain_exists_in_array "$domain" "${priority_group[@]}"; then
                candidates+=("$domain")
            fi
        done
        if [[ ${#candidates[@]} -eq 0 ]]; then
            candidates=("${AVAILABLE_DOMAINS[@]}")
        fi
    else
        candidates=("${AVAILABLE_DOMAINS[@]}")
    fi

    local top_n="$PRIMARY_ADAPTIVE_TOP_N"
    [[ "$top_n" =~ ^[0-9]+$ ]] || top_n=5
    ((top_n < 1)) && top_n=1
    if ((top_n > ${#candidates[@]})); then
        top_n=${#candidates[@]}
    fi

    # shellcheck disable=SC2034 # Used via nameref in pick_random_from_array.
    local -a top_candidates=("${candidates[@]:0:top_n}")
    local selected
    if ! selected=$(pick_random_from_array top_candidates); then
        selected="${AVAILABLE_DOMAINS[0]}"
    fi
    printf '%s' "$selected"
}

build_domain_plan() {
    local needed="$1"
    local include_primary="$2"
    DOMAIN_SELECTION_PLAN=()

    if ((needed < 1)); then
        return 1
    fi
    if [[ ${#AVAILABLE_DOMAINS[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ "$SPIDER_MODE" != "true" ]]; then
        local base_domain="${AVAILABLE_DOMAINS[0]}"
        if [[ "$include_primary" == "true" ]]; then
            base_domain=$(select_primary_domain)
        fi
        local i
        for ((i = 0; i < needed; i++)); do
            DOMAIN_SELECTION_PLAN+=("$base_domain")
        done
        return 0
    fi

    local -a working=("${AVAILABLE_DOMAINS[@]}")
    if [[ "$include_primary" == "true" ]]; then
        local primary
        primary=$(select_primary_domain)
        DOMAIN_SELECTION_PLAN+=("$primary")

        local -a filtered=()
        local removed=false
        local d
        for d in "${working[@]}"; do
            if [[ "$removed" == "false" && "$d" == "$primary" ]]; then
                removed=true
                continue
            fi
            filtered+=("$d")
        done
        if [[ ${#filtered[@]} -gt 0 ]]; then
            working=("${filtered[@]}")
        fi
    fi

    while ((${#DOMAIN_SELECTION_PLAN[@]} < needed)); do
        local -a cycle=("${working[@]}")
        if [[ ${#cycle[@]} -eq 0 ]]; then
            cycle=("${AVAILABLE_DOMAINS[@]}")
        fi
        shuffle_array_inplace cycle
        local prev_domain=""
        if [[ ${#DOMAIN_SELECTION_PLAN[@]} -gt 0 ]]; then
            prev_domain="${DOMAIN_SELECTION_PLAN[$((${#DOMAIN_SELECTION_PLAN[@]} - 1))]}"
        fi
        local -a diverse_cycle=()
        build_diverse_cycle_from_pool cycle diverse_cycle "$prev_domain"
        if [[ ${#diverse_cycle[@]} -gt 0 ]]; then
            cycle=("${diverse_cycle[@]}")
        fi

        local domain
        for domain in "${cycle[@]}"; do
            DOMAIN_SELECTION_PLAN+=("$domain")
            if ((${#DOMAIN_SELECTION_PLAN[@]} >= needed)); then
                break
            fi
        done
    done
    return 0
}

detect_reality_dest() {
    local domain="$1"

    if ! is_valid_domain "$domain"; then
        debug_file "Invalid domain rejected in detect_reality_dest: $domain"
        echo "443"
        return 0
    fi

    if [[ "${SKIP_REALITY_CHECK:-false}" == "true" ]]; then
        echo "443"
        return 0
    fi
    local -a tested_ports=()
    mapfile -t tested_ports < <(split_list "$REALITY_TEST_PORTS")
    if [[ ${#tested_ports[@]} -eq 0 ]]; then
        tested_ports=(443 8443 2053 2083 2087)
    fi

    if ! command -v openssl > /dev/null 2>&1; then
        echo "443"
        return 0
    fi
    if ! command -v timeout > /dev/null 2>&1; then
        echo "443"
        return 0
    fi

    local port
    for port in "${tested_ports[@]}"; do
        # shellcheck disable=SC2016 # Single quotes intentional - args passed via $1/$2
        if timeout 2 bash -c 'echo | openssl s_client -brief -connect "$1:$2" -servername "$1" 2>&1' _ "$domain" "$port" | grep -Eq 'CONNECTED|CONNECTION ESTABLISHED'; then
            echo "$port"
            return 0
        fi
    done

    echo "443"
}

is_port_safe() {
    local port="$1"
    local -a skip_ports=(22 80 8080 3306 5432 6379 27017)
    local p
    for p in "${skip_ports[@]}"; do
        [[ $port -eq $p ]] && return 1
    done
    if ((port >= 32768 && port <= 60999)); then
        return 1
    fi
    return 0
}

find_free_port() {
    local start_port="$1"
    local excluded="$2" # space-separated list of ports to exclude
    local port="$start_port"
    local max_attempts=70000
    local attempts=0

    if ((port < 1024)); then
        port=1024
    fi
    if ((port > 65535)); then
        port=1024
    fi
    if ((port >= 32768 && port <= 60999)); then
        port=61000
    fi

    while ((attempts < max_attempts)); do
        if is_port_safe "$port" && ! port_is_listening "$port"; then
            if [[ " $excluded " != *" $port "* ]]; then
                echo "$port"
                return 0
            fi
        fi
        port=$((port + 1))
        if ((port > 65535)); then
            port=1024 # Wrap to start of user ports
        fi
        if ((port >= 32768 && port <= 60999)); then
            port=61000
        fi
        attempts=$((attempts + 1))
    done
    return 1
}

allocate_ports() {
    log STEP "Выделяем порты..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Используем существующие порты: ${PORTS[*]}"
        return 0
    fi

    PORTS=()
    PORTS_V6=()
    # shellcheck disable=SC2153 # START_PORT is a global variable from lib.sh
    local current_port=$START_PORT
    local ipv6_disabled=false
    local all_allocated=""

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local port
        port=$(find_free_port "$current_port" "$all_allocated") || {
            log ERROR "Нет доступных портов для IPv4"
            hint "Освободите порты: systemctl stop nginx apache2 или укажите другой --start-port"
            return 1
        }
        PORTS+=("$port")
        all_allocated="$all_allocated $port"
        current_port=$((port + 1))

        if [[ "$HAS_IPV6" == true && "$ipv6_disabled" == false ]]; then
            local v6_start
            if ((port < 4535)); then
                v6_start=$((port + 61000))
                if ((v6_start > 65535)); then
                    v6_start=61000
                fi
            else
                v6_start=$((port + 10000))
                if ((v6_start > 65535)); then
                    v6_start=$((61000 + (port % 4535)))
                fi
            fi

            local v6_port
            v6_port=$(find_free_port "$v6_start" "$all_allocated") || {
                log WARN "Не удалось выделить IPv6 порт; IPv6 отключён"
                HAS_IPV6=false
                ipv6_disabled=true
            }

            if [[ "$HAS_IPV6" == true ]]; then
                PORTS_V6+=("$v6_port")
                all_allocated="$all_allocated $v6_port"
            fi
        fi

        progress_bar $((i + 1)) "$NUM_CONFIGS"
    done

    log OK "Порты выделены (IPv4: ${PORTS[*]})"
    if [[ "$HAS_IPV6" == true ]]; then
        log INFO "Порты IPv6: ${PORTS_V6[*]}"
    fi
}

verify_ports_available() {
    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        return 0
    fi
    local port
    for port in "${PORTS[@]}"; do
        if port_is_listening "$port"; then
            log ERROR "Порт уже занят: ${port}"
            return 1
        fi
    done
    if [[ "$HAS_IPV6" == true ]]; then
        for port in "${PORTS_V6[@]}"; do
            [[ -n "$port" ]] || continue
            if port_is_listening "$port"; then
                log ERROR "IPv6 порт уже занят: ${port}"
                return 1
            fi
        done
    fi
    return 0
}

count_listening_ports() {
    local listening=0
    local expected=0
    local port
    for port in "$@"; do
        [[ -n "$port" ]] || continue
        expected=$((expected + 1))
        if port_is_listening "$port"; then
            listening=$((listening + 1))
        fi
    done
    printf '%s %s\n' "$listening" "$expected"
}

generate_short_id() {
    local sid_bytes
    sid_bytes=$(rand_between "$SHORT_ID_BYTES_MIN" "$SHORT_ID_BYTES_MAX")
    if [[ ! "$sid_bytes" =~ ^[0-9]+$ ]] || ((sid_bytes < 8)); then
        sid_bytes=8
    fi
    openssl rand -hex "$sid_bytes"
}

generate_uuid() {
    local candidate=""
    if command -v uuidgen > /dev/null 2>&1; then
        candidate=$(uuidgen 2> /dev/null || true)
        if [[ "$candidate" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        candidate=$(cat /proc/sys/kernel/random/uuid 2> /dev/null || true)
        if [[ "$candidate" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    if command -v openssl > /dev/null 2>&1; then
        local hex
        hex=$(openssl rand -hex 16 2> /dev/null || true)
        if [[ "$hex" =~ ^[0-9a-fA-F]{32}$ ]]; then
            hex="${hex,,}"
            local time_hi clock_seq clock_seq_hi
            time_hi="4${hex:13:3}"
            clock_seq="${hex:16:4}"
            clock_seq_hi=$((16#${clock_seq:0:2}))
            clock_seq_hi=$(((clock_seq_hi & 0x3f) | 0x80))
            printf -v clock_seq '%02x%s' "$clock_seq_hi" "${clock_seq:2:2}"
            printf '%s-%s-%s-%s-%s\n' \
                "${hex:0:8}" "${hex:8:4}" "$time_hi" "$clock_seq" "${hex:20:12}"
            return 0
        fi
    fi
    return 1
}

generate_x25519_keypair() {
    local key_output
    key_output=$("$XRAY_BIN" x25519 2>&1)

    local priv
    priv=$(echo "$key_output" | awk -F': ' 'tolower($0) ~ /private/ {print $2}' | tr -d ' \r\n')
    if [[ -z "$priv" ]]; then
        log ERROR "Не удалось получить private key из xray x25519"
        debug_file "xray x25519 output: $key_output"
        return 1
    fi

    local pub
    pub=$(echo "$key_output" | awk -F': ' 'tolower($0) ~ /public/ {print $2}' | tr -d ' \r\n')
    if [[ -z "$pub" ]]; then
        pub=$(echo "$key_output" | awk -F': ' 'tolower($0) ~ /password/ {print $2}' | tr -d ' \r\n')
    fi
    if [[ -z "$pub" ]]; then
        log ERROR "Не удалось получить public key из xray x25519"
        debug_file "xray x25519 output: $key_output"
        return 1
    fi

    printf '%s\t%s\n' "$priv" "$pub"
}

pick_random_from_array() {
    # shellcheck disable=SC2178 # Nameref intentionally points to array variable name.
    local -n _arr="$1"
    local _len="${#_arr[@]}"
    if ((_len < 1)); then
        return 1
    fi
    local _idx
    _idx=$(rand_between 0 $((_len - 1)))
    printf '%s' "${_arr[$_idx]}"
}

select_legacy_transport_endpoint() {
    local domain="$1"
    local -a grpc_fallbacks=(
        "cdn.storage.v1.UploadService"
        "api.internal.health.v1.HealthCheck"
        "cloud.metrics.v1.CollectorService"
    )
    local -a grpc_candidates=()
    local grpc_pool="${TRANSPORT_ENDPOINT_SEEDS[$domain]:-}"

    if [[ -n "$grpc_pool" ]]; then
        local -a grpc_array=()
        local svc
        read -r -a grpc_array <<< "$grpc_pool"
        for svc in "${grpc_array[@]}"; do
            if is_valid_grpc_service_name "$svc"; then
                grpc_candidates+=("$svc")
            else
                log WARN "Пропускаем невалидный gRPC serviceName для ${domain}: ${svc}"
            fi
        done
    fi
    if ((${#grpc_candidates[@]} == 0)); then
        grpc_candidates=("${grpc_fallbacks[@]}")
    fi

    pick_random_from_array grpc_candidates
}

legacy_transport_endpoint_to_http2_path() {
    local service_name="$1"
    if [[ "$service_name" == /* ]]; then
        printf '%s' "$service_name"
        return 0
    fi
    local path="${service_name//./\/}"
    if [[ -z "$path" ]]; then
        path="api/v1/data"
    fi
    printf '/%s' "$path"
}

sanitize_xhttp_path_segment() {
    local value="${1:-}"
    value="${value,,}"
    value="${value//_/-}"
    value=$(printf '%s' "$value" | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')
    [[ -n "$value" ]] || value="edge"
    printf '%s' "${value:0:24}"
}

generate_xhttp_path_for_domain() {
    local domain="$1"
    local left="${domain%%.*}"
    local rest="${domain#*.}"
    if [[ "$rest" == "$domain" ]]; then
        rest="$left"
    else
        rest="${rest%%.*}"
    fi
    local seg1 seg2 suffix
    seg1=$(sanitize_xhttp_path_segment "$left")
    seg2=$(sanitize_xhttp_path_segment "$rest")
    suffix=$(openssl rand -hex 4 2> /dev/null || printf '%08x' "$(rand_between 0 2147483647)")
    local candidate="/${seg1}/api/${seg2}/${suffix}"
    if ! is_valid_xhttp_path "$candidate"; then
        candidate="/${seg1}/sync/${suffix}"
    fi
    printf '%s' "$candidate"
}

build_inbound_profile_for_domain() {
    local domain="$1"
    local fp_pool_name="$2"
    local -n _fp_pool="$fp_pool_name"

    local sni_pool="${SNI_POOLS[$domain]:-$domain}"
    local -a sni_array=()
    read -r -a sni_array <<< "$sni_pool"
    local -a safe_sni_array=()
    local sni_candidate
    for sni_candidate in "${sni_array[@]}"; do
        if is_valid_domain "$sni_candidate"; then
            safe_sni_array+=("$sni_candidate")
        fi
    done
    if ((${#safe_sni_array[@]} == 0)); then
        safe_sni_array=("$domain")
    fi
    sni_array=("${safe_sni_array[@]}")

    PROFILE_SNI=""
    if ! PROFILE_SNI=$(pick_random_from_array sni_array); then
        PROFILE_SNI="$domain"
        sni_array=("$domain")
    fi
    if [[ "$DOMAIN_CHECK" == "true" && "$PROFILE_SNI" != "$domain" ]]; then
        if ! check_domain_alive "$PROFILE_SNI"; then
            log WARN "SNI ${PROFILE_SNI} недоступен; fallback на ${domain}"
            PROFILE_SNI="$domain"
        fi
    fi

    local -a server_names=("$PROFILE_SNI")
    local _sn
    for _sn in "${sni_array[@]}"; do
        [[ "$_sn" == "$PROFILE_SNI" ]] && continue
        server_names+=("$_sn")
        [[ ${#server_names[@]} -ge 3 ]] && break
    done
    PROFILE_SNI_JSON=$(printf '%s\n' "${server_names[@]}" | jq -R . | jq -s .)

    PROFILE_TRANSPORT_ENDPOINT=""
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        PROFILE_TRANSPORT_ENDPOINT=$(generate_xhttp_path_for_domain "$domain")
    else
        PROFILE_TRANSPORT_ENDPOINT=$(select_legacy_transport_endpoint "$domain")
    fi
    if ! PROFILE_FP=$(pick_random_from_array _fp_pool); then
        PROFILE_FP="chrome"
    fi

    local dest_port
    dest_port=$(detect_reality_dest "$domain")
    PROFILE_DEST="${domain}:${dest_port}"

    PROFILE_KEEPALIVE=$(rand_between "$TCP_KEEPALIVE_MIN" "$TCP_KEEPALIVE_MAX")
    PROFILE_GRPC_IDLE=$(rand_between "$GRPC_IDLE_TIMEOUT_MIN" "$GRPC_IDLE_TIMEOUT_MAX")
    PROFILE_GRPC_HEALTH=$(rand_between "$GRPC_HEALTH_TIMEOUT_MIN" "$GRPC_HEALTH_TIMEOUT_MAX")

    PROFILE_TRANSPORT_PAYLOAD="$PROFILE_TRANSPORT_ENDPOINT"
    if [[ "$TRANSPORT" == "http2" ]]; then
        PROFILE_TRANSPORT_PAYLOAD=$(legacy_transport_endpoint_to_http2_path "$PROFILE_TRANSPORT_ENDPOINT")
    fi
}

generate_profile_inbound_json() {
    local port="$1"
    local uuid="$2"
    local private_key="$3"
    local short_id="$4"
    local decryption_value="${5:-none}"

    generate_inbound_json \
        "$port" "$uuid" "$PROFILE_DEST" "$PROFILE_SNI_JSON" "$private_key" "$short_id" \
        "$PROFILE_FP" "$PROFILE_TRANSPORT_ENDPOINT" "$PROFILE_KEEPALIVE" "$PROFILE_GRPC_IDLE" "$PROFILE_GRPC_HEALTH" \
        "$TRANSPORT" "$PROFILE_TRANSPORT_PAYLOAD" "$decryption_value" "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}"
}

generate_keys() {
    log STEP "Генерируем криптографические ключи..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Ключи не перегенерируются (используем текущие)"
        return 0
    fi

    PRIVATE_KEYS=()
    PUBLIC_KEYS=()
    UUIDS=()
    SHORT_IDS=()

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local pair priv pub
        pair=$(generate_x25519_keypair) || return 1
        IFS=$'\t' read -r priv pub <<< "$pair"
        PRIVATE_KEYS+=("$priv")
        PUBLIC_KEYS+=("$pub")

        local uuid
        uuid=$(generate_uuid) || {
            log ERROR "Не удалось сгенерировать UUID"
            return 1
        }
        UUIDS+=("$uuid")

        SHORT_IDS+=("$(generate_short_id)")

        progress_bar $((i + 1)) "$NUM_CONFIGS"
    done

    log OK "Ключи сгенерированы"
}

PROFILE_SNI=""
PROFILE_SNI_JSON='[]'
PROFILE_FP="chrome"
PROFILE_DEST=""
PROFILE_KEEPALIVE=30
PROFILE_GRPC_IDLE=60
PROFILE_GRPC_HEALTH=20
PROFILE_TRANSPORT_PAYLOAD=""
DOMAIN_SELECTION_PLAN=()
