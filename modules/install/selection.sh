#!/usr/bin/env bash
# shellcheck shell=bash

: "${SPIDER_MODE:=true}"
: "${DOMAIN_TIER:=tier_ru}"
: "${TRANSPORT:=xhttp}"
: "${START_PORT:=443}"
: "${NUM_CONFIGS:=5}"
: "${REUSE_EXISTING_CONFIG:=false}"
: "${XRAY_DOMAIN_PROFILE:=}"
: "${XRAY_DOMAIN_TIER:=}"
: "${ADVANCED_MODE:=false}"
: "${NON_INTERACTIVE:=false}"
: "${AUTO_PROFILE_MODE:=false}"
: "${XRAY_NUM_CONFIGS:=}"
: "${RED:=}"
: "${NC:=}"

auto_configure() {
    SPIDER_MODE=$(parse_bool "$SPIDER_MODE" true)
    validate_install_config
    log OK "Авто-конфигурация: ${DOMAIN_TIER}, transport=${TRANSPORT}, порт ${START_PORT}, $(format_russian_count_noun "$NUM_CONFIGS" "конфиг" "конфига" "конфигов"), spider=${SPIDER_MODE}"
}
auto_profile_default_num_configs() {
    local tier_raw="${1:-tier_ru}"
    local tier
    if ! tier=$(normalize_domain_tier "$tier_raw"); then
        tier="tier_ru"
    fi
    case "$tier" in
        tier_global_ms10) echo 5 ;;
        *) echo 5 ;;
    esac
}

ask_domain_profile() {
    local has_tty=false
    if [[ -t 0 || -t 1 || -t 2 ]]; then
        has_tty=true
    fi
    AUTO_PROFILE_MODE=false

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        local requested_profile="${XRAY_DOMAIN_PROFILE:-${XRAY_DOMAIN_TIER:-}}"
        if [[ -n "$requested_profile" ]]; then
            local installed_tier requested_tier
            installed_tier="${DOMAIN_TIER:-tier_ru}"
            if ! installed_tier=$(normalize_domain_tier "$installed_tier" 2> /dev/null); then
                installed_tier="tier_ru"
            fi
            if requested_tier=$(normalize_domain_tier "$requested_profile" 2> /dev/null); then
                if [[ "$requested_tier" != "$installed_tier" ]]; then
                    log WARN "REUSE_EXISTING=true: запрошенный профиль ${requested_profile} игнорируется (используется установленный ${installed_tier})"
                fi
            else
                log WARN "REUSE_EXISTING=true: запрошенный профиль ${requested_profile} невалиден и игнорируется"
            fi
        fi
        return 0
    fi

    if [[ -n "${XRAY_DOMAIN_PROFILE:-}" ]] || [[ -n "${XRAY_DOMAIN_TIER:-}" ]]; then
        local explicit_profile="${XRAY_DOMAIN_PROFILE:-${XRAY_DOMAIN_TIER:-$DOMAIN_TIER}}"
        if is_legacy_global_profile_alias "$explicit_profile"; then
            log WARN "Профиль ${explicit_profile} является legacy-алиасом; используйте global-50 или global-50-auto"
        fi
        if is_auto_domain_profile_alias "$explicit_profile"; then
            AUTO_PROFILE_MODE=true
        fi
        if ! DOMAIN_TIER=$(normalize_domain_tier "$explicit_profile"); then
            DOMAIN_TIER="tier_ru"
        fi
        if [[ "$AUTO_PROFILE_MODE" == "true" ]]; then
            log INFO "Используем авто-профиль доменов: ${explicit_profile} -> $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
        else
            log INFO "Используем профиль доменов из параметров: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
        fi
        return 0
    fi

    if [[ "${ADVANCED_MODE:-false}" != "true" ]]; then
        DOMAIN_TIER="tier_ru"
        AUTO_PROFILE_MODE=true
        log INFO "Минимальный install path: профиль доменов ru-auto (${DOMAIN_TIER})"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        DOMAIN_TIER="tier_ru"
        AUTO_PROFILE_MODE=true
        log INFO "Non-interactive режим: профиль доменов по умолчанию ru-auto (${DOMAIN_TIER})"
        return 0
    fi

    if [[ "$has_tty" != "true" ]]; then
        log ERROR "Не удалось открыть /dev/tty для выбора профиля доменов"
        exit 1
    fi

    local tty_read_fd="" tty_write_fd=""
    if ! open_interactive_tty_fds tty_read_fd tty_write_fd; then
        log ERROR "Не удалось открыть /dev/tty для выбора профиля доменов"
        exit 1
    fi

    printf '\n' >&"$tty_write_fd"
    local input
    while true; do
        printf '%s\n' "Выберите профиль доменов:" >&"$tty_write_fd"
        printf '%s\n' "  1) ru (ручной ввод числа ключей, до 100)" >&"$tty_write_fd"
        printf '%s\n' "  2) global-50 (ручной ввод числа ключей, до 15)" >&"$tty_write_fd"
        printf '%s\n' "  3) ru-auto (автоматически: 5 ключей)" >&"$tty_write_fd"
        printf '%s\n' "  4) global-50-auto (автоматически: 5 ключей)" >&"$tty_write_fd"
        if ! printf "Профиль [1/2/3/4]: " >&"$tty_write_fd"; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось вывести запрос выбора профиля в /dev/tty"
            exit 1
        fi
        if ! read -r -u "$tty_read_fd" input; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось прочитать выбор профиля из /dev/tty"
            exit 1
        fi
        input=$(normalize_tty_input "$input")
        case "${input,,}" in
            "" | 1 | ru | russia | rf | tier_ru)
                DOMAIN_TIER="tier_ru"
                AUTO_PROFILE_MODE=false
                break
                ;;
            2 | global | global-50 | g50 | tier_global_50)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=false
                break
                ;;
            global-ms10 | ms10 | tier_global_ms10)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=false
                log WARN "Профиль ${input} является legacy-алиасом; используйте global-50"
                break
                ;;
            3 | ru-auto | russia-auto | rf-auto | tier_ru_auto)
                DOMAIN_TIER="tier_ru"
                AUTO_PROFILE_MODE=true
                break
                ;;
            4 | global-auto | global-50-auto | g50-auto | tier_global_50_auto)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=true
                break
                ;;
            global-ms10-auto | ms10-auto | tier_global_ms10_auto)
                DOMAIN_TIER="tier_global_ms10"
                AUTO_PROFILE_MODE=true
                log WARN "Профиль ${input} является legacy-алиасом; используйте global-50-auto"
                break
                ;;
            *)
                printf '%bВведите 1, 2, 3 или 4 (пустой ввод = ru)%b\n' "$RED" "$NC" >&"$tty_write_fd"
                ;;
        esac
    done
    exec {tty_read_fd}<&-
    exec {tty_write_fd}>&-
    if ! DOMAIN_TIER=$(normalize_domain_tier "$DOMAIN_TIER"); then
        DOMAIN_TIER="tier_ru"
    fi
    if [[ "$AUTO_PROFILE_MODE" == "true" ]]; then
        log OK "Профиль доменов: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER}, auto)"
    else
        log OK "Профиль доменов: $(domain_tier_label "$DOMAIN_TIER") (${DOMAIN_TIER})"
    fi
    echo ""
}

ask_num_configs() {
    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        return 0
    fi

    local max_configs
    max_configs=$(max_configs_for_tier "$DOMAIN_TIER")

    if [[ -n "${XRAY_NUM_CONFIGS:-}" ]]; then
        if [[ "$XRAY_NUM_CONFIGS" =~ ^[0-9]+$ ]] && ((XRAY_NUM_CONFIGS >= 1 && XRAY_NUM_CONFIGS <= max_configs)); then
            NUM_CONFIGS="$XRAY_NUM_CONFIGS"
            log INFO "Используем переданное количество конфигов: ${NUM_CONFIGS}"
            return 0
        fi
        log ERROR "Некорректное значение --num-configs: ${XRAY_NUM_CONFIGS} (допустимо 1-${max_configs})"
        exit 1
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        NUM_CONFIGS=$(auto_profile_default_num_configs "$DOMAIN_TIER")
        log INFO "Non-interactive режим: используем авто-количество конфигов (${NUM_CONFIGS}); для явного выбора используйте --num-configs <n>"
        return 0
    fi

    local tty_read_fd="" tty_write_fd=""
    if ! open_interactive_tty_fds tty_read_fd tty_write_fd; then
        log ERROR "Не удалось открыть /dev/tty для обязательного ввода NUM_CONFIGS"
        exit 1
    fi

    printf '\n' >&"$tty_write_fd"
    local input
    while true; do
        if ! printf "Количество конфигов (1-%s): " "$max_configs" >&"$tty_write_fd"; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось вывести запрос NUM_CONFIGS в /dev/tty"
            exit 1
        fi
        if ! read -r -u "$tty_read_fd" input; then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            log ERROR "Не удалось прочитать значение NUM_CONFIGS из /dev/tty"
            exit 1
        fi
        input=$(normalize_tty_input "$input")
        if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= max_configs)); then
            exec {tty_read_fd}<&-
            exec {tty_write_fd}>&-
            NUM_CONFIGS="$input"
            log OK "Количество конфигов: ${NUM_CONFIGS}"
            echo ""
            return 0
        fi
        printf '%bВведите число от 1 до %s (пустой ввод не допускается)%b\n' "$RED" "$max_configs" "$NC" >&"$tty_write_fd"
    done
}
