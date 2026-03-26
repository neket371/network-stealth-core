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

CONFIG_RUNTIME_PROFILES_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/runtime_profiles.sh"
if [[ ! -f "$CONFIG_RUNTIME_PROFILES_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_RUNTIME_PROFILES_MODULE="$XRAY_DATA_DIR/modules/config/runtime_profiles.sh"
fi
if [[ ! -f "$CONFIG_RUNTIME_PROFILES_MODULE" ]]; then
    echo "ERROR: не найден модуль runtime profiles: $CONFIG_RUNTIME_PROFILES_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/config/runtime_profiles.sh
source "$CONFIG_RUNTIME_PROFILES_MODULE"

setup_domains() {
    log STEP "Настраиваем домены (Spider Mode v2)..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Используем домены из текущей конфигурации"
        return 0
    fi

    local tiers_file="$XRAY_TIERS_FILE"

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
    declare -g DOMAIN_TIER_USES_CATALOG=false

    local -a tier_domains=()
    local used_catalog_tier=false
    if [[ "$selected_tier" != "custom" ]]; then
        if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "$selected_tier"; then
            mapfile -t tier_domains < <(load_tier_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "$selected_tier")
            populate_domain_metadata_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "$selected_tier" || true
            used_catalog_tier=true
        else
            if [[ -z "$tiers_file" || ! -f "$tiers_file" ]]; then
                log ERROR "Файл tiers не найден: $tiers_file"
                return 1
            fi
            mapfile -t tier_domains < <(load_tier_domains_from_file "$tiers_file" "$selected_tier")
        fi
        if [[ ${#tier_domains[@]} -eq 0 && "$selected_tier" != "tier_ru" ]]; then
            log WARN "Тир ${selected_tier} пустой; используем tier_ru"
            selected_tier="tier_ru"
            DOMAIN_TIER="tier_ru"
            if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "tier_ru"; then
                mapfile -t tier_domains < <(load_tier_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "tier_ru")
                populate_domain_metadata_from_catalog "$XRAY_DOMAIN_CATALOG_FILE" "tier_ru" || true
                used_catalog_tier=true
            else
                if [[ -z "$tiers_file" || ! -f "$tiers_file" ]]; then
                    log ERROR "Файл tiers не найден: $tiers_file"
                    return 1
                fi
                mapfile -t tier_domains < <(load_tier_domains_from_file "$tiers_file" "tier_ru")
                used_catalog_tier=false
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
        DOMAIN_TIER_USES_CATALOG=false
    else
        AVAILABLE_DOMAINS=("${tier_domains[@]}")
        DOMAIN_TIER_USES_CATALOG="$used_catalog_tier"
    fi
    seed_domain_metadata_from_list "${AVAILABLE_DOMAINS[@]}"
    load_provider_family_field_penalties

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
    if [[ "$DOMAIN_TIER_USES_CATALOG" != "true" && -n "$XRAY_SNI_POOLS_FILE" && -f "$XRAY_SNI_POOLS_FILE" ]]; then
        load_map_file "$XRAY_SNI_POOLS_FILE" SNI_POOLS || return 1
    elif [[ "$DOMAIN_TIER_USES_CATALOG" != "true" ]]; then
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
            log WARN "Файл legacy transport endpoint seeds (migration-only) не найден: $XRAY_TRANSPORT_ENDPOINTS_FILE"
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
    local -a missing_legacy_endpoints=()
    local domain
    for domain in "${AVAILABLE_DOMAINS[@]}"; do
        [[ -n "${SNI_POOLS[$domain]:-}" ]] || missing_sni+=("$domain")
        if transport_is_legacy "$TRANSPORT"; then
            [[ -n "${TRANSPORT_ENDPOINT_SEEDS[$domain]:-}" ]] || missing_legacy_endpoints+=("$domain")
        fi
    done

    if [[ ${#missing_sni[@]} -eq 0 && ${#missing_legacy_endpoints[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ ${#missing_sni[@]} -gt 0 ]]; then
        if [[ "${DOMAIN_TIER_USES_CATALOG:-false}" == "true" ]]; then
            log WARN "Домены без SNI pool в catalog/fallback sources: ${missing_sni[*]}"
        else
            log WARN "Домены без SNI pool: ${missing_sni[*]}"
        fi
    fi
    if [[ ${#missing_legacy_endpoints[@]} -gt 0 ]]; then
        log WARN "Домены без legacy transport endpoint seeds: ${missing_legacy_endpoints[*]}"
    fi

    if [[ "$strict" == "true" ]]; then
        if [[ ${#missing_legacy_endpoints[@]} -gt 0 ]]; then
            log ERROR "Неполное покрытие legacy migration metadata для ${DOMAIN_TIER}. Исправьте transport_endpoints.map для legacy transport coverage."
        elif [[ "${DOMAIN_TIER_USES_CATALOG:-false}" == "true" ]]; then
            log ERROR "Неполное покрытие planner metadata для ${DOMAIN_TIER}. Исправьте catalog.json (и fallback sources только при необходимости compatibility)."
        else
            log ERROR "Неполное покрытие planner sources для ${DOMAIN_TIER}. Исправьте sni_pools.map и transport_endpoints.map только для legacy migration coverage."
        fi
        return 1
    fi
}

load_priority_domains() {
    local -a priority=()
    if catalog_supports_tier "${XRAY_DOMAIN_CATALOG_FILE:-}" "priority"; then
        mapfile -t priority < <(load_priority_domains_from_catalog "$XRAY_DOMAIN_CATALOG_FILE")
    fi
    if [[ ${#priority[@]} -eq 0 ]] && [[ -n "${XRAY_DOMAIN_CATALOG_FILE:-}" && -f "${XRAY_DOMAIN_CATALOG_FILE:-}" ]] && command -v jq > /dev/null 2>&1; then
        mapfile -t priority < <(
            jq -r '
                [.tiers.tier_ru[]?, .tiers.tier_global_ms10[]?]
                | flatten
                | map(select((.priority // 0) > 0))
                | sort_by(-(.priority // 0), .domain)
                | .[].domain
            ' "$XRAY_DOMAIN_CATALOG_FILE" 2> /dev/null |
                while IFS= read -r domain; do
                    domain=$(normalize_catalog_text "$domain")
                    [[ -n "$domain" ]] || continue
                    printf '%s\n' "$domain"
                done
        )
    fi
    if [[ -n "$XRAY_TIERS_FILE" && -f "$XRAY_TIERS_FILE" ]]; then
        if [[ ${#priority[@]} -eq 0 ]]; then
            mapfile -t priority < <(load_tier_domains_from_file "$XRAY_TIERS_FILE" "priority")
        fi
    fi
    printf '%s\n' "${priority[@]}"
}

load_provider_family_field_penalties() {
    declare -gA DOMAIN_PROVIDER_FAMILY_FIELD_PENALTIES=()

    [[ -n "${MEASUREMENTS_SUMMARY_FILE:-}" && -f "${MEASUREMENTS_SUMMARY_FILE:-}" ]] || return 0
    command -v jq > /dev/null 2>&1 || return 0
    jq empty "$MEASUREMENTS_SUMMARY_FILE" > /dev/null 2>&1 || return 0

    local family penalty
    while IFS=$'\t' read -r family penalty; do
        family="${family//$'\r'/}"
        penalty="${penalty//$'\r'/}"
        [[ -n "$family" ]] || continue
        [[ "$penalty" =~ ^-?[0-9]+$ ]] || penalty=0
        DOMAIN_PROVIDER_FAMILY_FIELD_PENALTIES["$family"]="$penalty"
    done < <(
        jq -r '
            .provider_family_stats[]?
            | select((.provider_family // "") != "")
            | [.provider_family, (.field_penalty // 0)]
            | @tsv
        ' "$MEASUREMENTS_SUMMARY_FILE" 2> /dev/null
    )
}

domain_provider_family_field_penalty() {
    local family="${1:-}"
    [[ -n "$family" ]] || {
        printf '%s\n' "0"
        return 0
    }
    if ! declare -p DOMAIN_PROVIDER_FAMILY_FIELD_PENALTIES > /dev/null 2>&1; then
        printf '%s\n' "0"
        return 0
    fi
    if [[ -n "${DOMAIN_PROVIDER_FAMILY_FIELD_PENALTIES[$family]:-}" ]]; then
        printf '%s\n' "${DOMAIN_PROVIDER_FAMILY_FIELD_PENALTIES[$family]}"
        return 0
    fi
    printf '%s\n' "0"
}

domain_priority_weight() {
    local domain="${1:-}"
    if ! declare -p DOMAIN_PRIORITY_MAP > /dev/null 2>&1; then
        printf '%s\n' "0"
        return 0
    fi
    local priority_value="${DOMAIN_PRIORITY_MAP[$domain]:-0}"
    [[ "$priority_value" =~ ^-?[0-9]+$ ]] || priority_value=0
    printf '%s\n' "$priority_value"
}

domain_risk_weight() {
    local domain="${1:-}"
    if ! declare -p DOMAIN_RISK_MAP > /dev/null 2>&1; then
        printf '%s\n' "10"
        return 0
    fi
    local risk="${DOMAIN_RISK_MAP[$domain]:-normal}"
    case "${risk,,}" in
        low | safe) printf '%s\n' "0" ;;
        normal | "") printf '%s\n' "10" ;;
        elevated | medium) printf '%s\n' "25" ;;
        high) printf '%s\n' "50" ;;
        critical) printf '%s\n' "80" ;;
        custom) printf '%s\n' "20" ;;
        *) printf '%s\n' "30" ;;
    esac
}

prioritize_cycle_for_field_conditions() {
    local pool_name="$1"
    local out_name="$2"
    local previous_domain="${3:-}"
    local previous_family=""
    local i domain family same_domain same_family penalty risk_weight priority priority_sort
    if [[ -n "$previous_domain" ]]; then
        previous_family=$(domain_provider_family_for "$previous_domain" 2> /dev/null || true)
    fi

    # shellcheck disable=SC2034 # nameref writes caller variable.
    local -n _pool="$pool_name"
    local -n _out_ref="$out_name"

    mapfile -t _out_ref < <(
        for i in "${!_pool[@]}"; do
            domain="${_pool[$i]}"
            [[ -n "$domain" ]] || continue
            family=$(domain_provider_family_for "$domain" 2> /dev/null || true)
            [[ -n "$family" ]] || family="$domain"
            same_domain=0
            same_family=0
            if [[ -n "$previous_domain" && "$domain" == "$previous_domain" ]]; then
                same_domain=1
            fi
            if [[ -n "$previous_family" && "$family" == "$previous_family" ]]; then
                same_family=1
            fi
            penalty=$(domain_provider_family_field_penalty "$family")
            [[ "$penalty" =~ ^-?[0-9]+$ ]] || penalty=0
            risk_weight=$(domain_risk_weight "$domain")
            priority=$(domain_priority_weight "$domain")
            priority_sort=$((-priority))
            printf '%d\t%d\t%06d\t%06d\t%08d\t%06d\t%s\n' \
                "$same_domain" \
                "$same_family" \
                "$penalty" \
                "$risk_weight" \
                "$priority_sort" \
                "$i" \
                "$domain"
        done | sort -t$'\t' -k1,1n -k2,2n -k3,3n -k4,4n -k5,5n -k6,6n | cut -f7-
    )
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
    local candidates_from_priority=false
    if [[ ${#priority_group[@]} -gt 0 ]]; then
        for domain in "${AVAILABLE_DOMAINS[@]}"; do
            if domain_exists_in_array "$domain" "${priority_group[@]}"; then
                candidates+=("$domain")
            fi
        done
        if [[ ${#candidates[@]} -eq 0 ]]; then
            candidates=("${AVAILABLE_DOMAINS[@]}")
        else
            candidates_from_priority=true
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

    if [[ "$candidates_from_priority" != "true" ]]; then
        shuffle_array_inplace candidates
    fi
    local -a ranked_candidates=()
    prioritize_cycle_for_field_conditions candidates ranked_candidates
    if [[ ${#ranked_candidates[@]} -gt 0 ]]; then
        candidates=("${ranked_candidates[@]}")
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
        local -a prioritized_cycle=()
        prioritize_cycle_for_field_conditions cycle prioritized_cycle "$prev_domain"
        if [[ ${#prioritized_cycle[@]} -gt 0 ]]; then
            cycle=("${prioritized_cycle[@]}")
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

DOMAIN_SELECTION_PLAN=()
