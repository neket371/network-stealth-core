#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # Writes shared globals used by sourced runtime modules.

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

cli_is_action() {
    local value="${1:-}"
    case "$value" in
        install | add-clients | add-keys | update | repair | migrate-stealth | diagnose | rollback | uninstall | status | logs | check-update)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cli_option_requires_value() {
    local option="$1"
    case "$option" in
        --config | --domain-tier | --domain-profile | --num-configs | --domain-check-timeout | --domain-check-parallelism | \
            --tiers-file | --sni-pools-file | --grpc-services-file | --start-port | --server-ip | --server-ip6 | --mux-mode | \
            --transport | --progress-mode | --xray-version | --xray-mirror | --minisign-mirror | --auto-update-oncalendar | \
            --auto-update-random-delay | --primary-domain-mode | --primary-pin-domain | --primary-adaptive-top-n | \
            --domain-quarantine-fail-streak | --domain-quarantine-cooldown-min)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cli_read_long_option_value() {
    local optarg="$1"
    if [[ "$optarg" == *=* ]]; then
        printf '%s' "${optarg#*=}"
        return 0
    fi
    printf '%s' "${!OPTIND:-}"
    OPTIND=$((OPTIND + 1))
}

cli_append_csv_value() {
    local var_name="$1"
    local value="$2"
    if [[ -z "${!var_name:-}" ]]; then
        printf -v "$var_name" '%s' "$value"
    else
        printf -v "$var_name" '%s' "${!var_name},${value}"
    fi
}

cli_handle_long_option() {
    local optarg="$1"
    local value

    case "$optarg" in
        help)
            print_usage
            exit 0
            ;;
        version)
            echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
            exit 0
            ;;
        yes | non-interactive)
            NON_INTERACTIVE=true
            ASSUME_YES=true
            ;;
        advanced)
            XRAY_ADVANCED="true"
            ;;
        dry-run)
            DRY_RUN=true
            ;;
        verbose)
            VERBOSE=true
            ;;
        allow-insecure-sha256)
            ALLOW_INSECURE_SHA256=true
            ;;
        require-minisign)
            REQUIRE_MINISIGN=true
            ;;
        no-require-minisign)
            REQUIRE_MINISIGN=false
            ;;
        allow-no-systemd)
            ALLOW_NO_SYSTEMD=true
            ;;
        no-allow-no-systemd)
            ALLOW_NO_SYSTEMD=false
            ;;
        config | config=*)
            XRAY_CONFIG_FILE="$(cli_read_long_option_value "$optarg")"
            ;;
        domain-tier | domain-tier=*)
            XRAY_DOMAIN_TIER="$(cli_read_long_option_value "$optarg")"
            ;;
        domain-profile | domain-profile=*)
            XRAY_DOMAIN_PROFILE="$(cli_read_long_option_value "$optarg")"
            ;;
        num-configs | num-configs=*)
            XRAY_NUM_CONFIGS="$(cli_read_long_option_value "$optarg")"
            ;;
        spider | spider-mode)
            XRAY_SPIDER_MODE="true"
            ;;
        no-spider)
            XRAY_SPIDER_MODE="false"
            ;;
        domain-check)
            DOMAIN_CHECK="true"
            ;;
        no-domain-check)
            DOMAIN_CHECK="false"
            ;;
        skip-reality-check)
            SKIP_REALITY_CHECK="true"
            ;;
        domain-check-timeout | domain-check-timeout=*)
            DOMAIN_CHECK_TIMEOUT="$(cli_read_long_option_value "$optarg")"
            ;;
        domain-check-parallelism | domain-check-parallelism=*)
            DOMAIN_CHECK_PARALLELISM="$(cli_read_long_option_value "$optarg")"
            ;;
        primary-domain-mode | primary-domain-mode=*)
            PRIMARY_DOMAIN_MODE="$(cli_read_long_option_value "$optarg")"
            ;;
        primary-pin-domain | primary-pin-domain=*)
            PRIMARY_PIN_DOMAIN="$(cli_read_long_option_value "$optarg")"
            ;;
        primary-adaptive-top-n | primary-adaptive-top-n=*)
            PRIMARY_ADAPTIVE_TOP_N="$(cli_read_long_option_value "$optarg")"
            ;;
        domain-quarantine-fail-streak | domain-quarantine-fail-streak=*)
            DOMAIN_QUARANTINE_FAIL_STREAK="$(cli_read_long_option_value "$optarg")"
            ;;
        domain-quarantine-cooldown-min | domain-quarantine-cooldown-min=*)
            DOMAIN_QUARANTINE_COOLDOWN_MIN="$(cli_read_long_option_value "$optarg")"
            ;;
        tiers-file | tiers-file=*)
            XRAY_TIERS_FILE="$(cli_read_long_option_value "$optarg")"
            ;;
        sni-pools-file | sni-pools-file=*)
            XRAY_SNI_POOLS_FILE="$(cli_read_long_option_value "$optarg")"
            ;;
        grpc-services-file | grpc-services-file=*)
            XRAY_GRPC_SERVICES_FILE="$(cli_read_long_option_value "$optarg")"
            ;;
        start-port | start-port=*)
            XRAY_START_PORT="$(cli_read_long_option_value "$optarg")"
            ;;
        server-ip | server-ip=*)
            SERVER_IP="$(cli_read_long_option_value "$optarg")"
            ;;
        server-ip6 | server-ip6=*)
            SERVER_IP6="$(cli_read_long_option_value "$optarg")"
            ;;
        mux-mode | mux-mode=*)
            MUX_MODE="$(cli_read_long_option_value "$optarg")"
            ;;
        transport | transport=*)
            XRAY_TRANSPORT="$(cli_read_long_option_value "$optarg")"
            ;;
        progress-mode | progress-mode=*)
            PROGRESS_MODE="$(cli_read_long_option_value "$optarg")"
            ;;
        keep-local-backups)
            KEEP_LOCAL_BACKUPS="true"
            ;;
        no-local-backups)
            KEEP_LOCAL_BACKUPS="false"
            ;;
        reuse-config)
            REUSE_EXISTING="true"
            ;;
        no-reuse-config)
            REUSE_EXISTING="false"
            ;;
        auto-rollback)
            AUTO_ROLLBACK="true"
            ;;
        no-auto-rollback)
            AUTO_ROLLBACK="false"
            ;;
        xray-version | xray-version=*)
            XRAY_VERSION="$(cli_read_long_option_value "$optarg")"
            ;;
        xray-mirror | xray-mirror=*)
            value="$(cli_read_long_option_value "$optarg")"
            cli_append_csv_value XRAY_MIRRORS "$value"
            ;;
        minisign-mirror | minisign-mirror=*)
            value="$(cli_read_long_option_value "$optarg")"
            cli_append_csv_value MINISIGN_MIRRORS "$value"
            ;;
        qr)
            QR_ENABLED="true"
            ;;
        no-qr)
            QR_ENABLED="false"
            ;;
        auto-update)
            AUTO_UPDATE="true"
            ;;
        no-auto-update)
            AUTO_UPDATE="false"
            ;;
        auto-update-oncalendar | auto-update-oncalendar=*)
            AUTO_UPDATE_ONCALENDAR="$(cli_read_long_option_value "$optarg")"
            ;;
        auto-update-random-delay | auto-update-random-delay=*)
            AUTO_UPDATE_RANDOM_DELAY="$(cli_read_long_option_value "$optarg")"
            ;;
        rollback)
            ACTION="rollback"
            local next="${!OPTIND:-}"
            if [[ -n "$next" && "$next" != --* ]]; then
                ROLLBACK_DIR="$next"
                OPTIND=$((OPTIND + 1))
            fi
            ;;
        uninstall)
            ACTION="uninstall"
            ;;
        update)
            ACTION="update"
            ;;
        repair)
            ACTION="repair"
            ;;
        migrate-stealth)
            ACTION="migrate-stealth"
            ;;
        diagnose)
            ACTION="diagnose"
            ;;
        *)
            log ERROR "Неизвестный аргумент: --$optarg"
            print_usage
            exit 1
            ;;
    esac
}

parse_args() {
    local args=("$@")
    local cmd=""
    local explicit_cmd=""
    local opts=()
    local pos=()
    local i=0

    while [[ $i -lt ${#args[@]} ]]; do
        local a="${args[$i]}"

        if [[ "$a" == "--" ]]; then
            i=$((i + 1))
            while [[ $i -lt ${#args[@]} ]]; do
                pos+=("${args[$i]}")
                i=$((i + 1))
            done
            break
        fi

        if [[ -z "$cmd" ]] && cli_is_action "$a"; then
            cmd="$a"
            explicit_cmd="$a"
            i=$((i + 1))
            continue
        fi

        if [[ "$a" == --* || "$a" == -* ]]; then
            opts+=("$a")

            if cli_option_requires_value "$a" && [[ "$a" != *=* ]]; then
                i=$((i + 1))
                if [[ $i -ge ${#args[@]} ]]; then
                    log ERROR "Не указан параметр для $a"
                    exit 1
                fi
                opts+=("${args[$i]}")
            elif [[ "$a" == --rollback && "$a" != *=* ]]; then
                local next="${args[$((i + 1))]:-}"
                if [[ -n "$next" && "$next" != --* ]]; then
                    i=$((i + 1))
                    opts+=("$next")
                fi
            fi
        else
            pos+=("$a")
        fi

        i=$((i + 1))
    done

    if [[ -n "$cmd" ]]; then
        set -- "${opts[@]}" "$cmd" "${pos[@]}"
    else
        set -- "${opts[@]}" "${pos[@]}"
    fi

    OPTIND=1
    while getopts ":h-:" opt; do
        case "$opt" in
            h)
                print_usage
                exit 0
                ;;
            -)
                cli_handle_long_option "$OPTARG"
                ;;
            \?)
                log ERROR "Неизвестный аргумент: -$OPTARG"
                print_usage
                exit 1
                ;;
            :)
                log ERROR "Не указан параметр для -$OPTARG"
                exit 1
                ;;
            *)
                log ERROR "Неизвестный аргумент: -$opt"
                exit 1
                ;;
        esac
    done

    shift $((OPTIND - 1))

    if [[ $# -gt 0 ]] && cli_is_action "$1"; then
        ACTION="$1"
        shift
    fi

    if [[ -z "$explicit_cmd" && "$ACTION" == "install" && $# -gt 0 ]]; then
        log ERROR "Неизвестная команда: $1"
        print_usage
        exit 1
    fi

    case "$ACTION" in
        rollback)
            if [[ -z "$ROLLBACK_DIR" && -n "${1:-}" && "${1:-}" != --* ]]; then
                ROLLBACK_DIR="$1"
                shift
            fi
            ;;
        logs)
            if [[ -n "${1:-}" && "${1:-}" != --* ]]; then
                # shellcheck disable=SC2034 # Used in health.sh
                LOGS_TARGET="$1"
                shift
            fi
            ;;
        add-clients | add-keys)
            if [[ -n "${1:-}" && "${1:-}" != --* ]]; then
                # shellcheck disable=SC2034 # Used in config.sh add_clients_flow
                ADD_CLIENTS_COUNT="$1"
                shift
            fi
            ;;
        *) ;;
    esac

    if [[ $# -gt 0 ]]; then
        log ERROR "Неожиданные позиционные аргументы для '${ACTION}': $*"
        print_usage
        exit 1
    fi
}

apply_runtime_overrides() {
    local action_is_add=false
    AUTO_PROFILE_MODE=false
    if [[ "$ACTION" == "add-clients" || "$ACTION" == "add-keys" ]]; then
        action_is_add=true
    fi

    KEEP_LOCAL_BACKUPS=$(parse_bool "$KEEP_LOCAL_BACKUPS" true)
    REUSE_EXISTING=$(parse_bool "$REUSE_EXISTING" true)
    AUTO_ROLLBACK=$(parse_bool "$AUTO_ROLLBACK" true)
    AUTO_UPDATE=$(parse_bool "$AUTO_UPDATE" true)
    ALLOW_INSECURE_SHA256=$(parse_bool "$ALLOW_INSECURE_SHA256" false)
    ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP=$(parse_bool "$ALLOW_UNVERIFIED_MINISIGN_BOOTSTRAP" false)
    REQUIRE_MINISIGN=$(parse_bool "$REQUIRE_MINISIGN" false)
    ALLOW_NO_SYSTEMD=$(parse_bool "$ALLOW_NO_SYSTEMD" false)
    GEO_VERIFY_HASH=$(parse_bool "$GEO_VERIFY_HASH" true)
    GEO_VERIFY_STRICT=$(parse_bool "$GEO_VERIFY_STRICT" false)
    DRY_RUN=$(parse_bool "$DRY_RUN" false)
    VERBOSE=$(parse_bool "$VERBOSE" false)
    DOMAIN_CHECK=$(parse_bool "$DOMAIN_CHECK" true)
    SKIP_REALITY_CHECK=$(parse_bool "$SKIP_REALITY_CHECK" false)
    DOMAIN_HEALTH_RANKING=$(parse_bool "$DOMAIN_HEALTH_RANKING" true)
    normalize_progress_mode
    normalize_runtime_common_ranges
    normalize_runtime_schedule_settings
    normalize_primary_domain_controls
    if [[ -z "$DOMAIN_HEALTH_FILE" ]]; then
        DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    fi
    if [[ "$DOMAIN_HEALTH_FILE" == *$'\n'* ]] || [[ "$DOMAIN_HEALTH_FILE" =~ [[:cntrl:]] ]]; then
        log WARN "Некорректный DOMAIN_HEALTH_FILE: содержит управляющие символы (используем default)"
        DOMAIN_HEALTH_FILE="/var/lib/xray/domain-health.json"
    fi
    if [[ -z "$DOWNLOAD_HOST_ALLOWLIST" ]]; then
        DOWNLOAD_HOST_ALLOWLIST="github.com,api.github.com,objects.githubusercontent.com,raw.githubusercontent.com,release-assets.githubusercontent.com,ghproxy.com"
    fi
    if [[ -z "${HEALTH_LOG:-}" ]]; then
        HEALTH_LOG="${XRAY_LOGS%/}/xray-health.log"
    fi
    if [[ "$HEALTH_LOG" == *$'\n'* ]] || [[ "$HEALTH_LOG" =~ [[:cntrl:]] ]]; then
        log WARN "Некорректный HEALTH_LOG: содержит управляющие символы (используем default)"
        HEALTH_LOG="${XRAY_LOGS%/}/xray-health.log"
    fi
    if [[ -z "$XRAY_DOMAIN_PROFILE" && -n "${DOMAIN_PROFILE:-}" ]]; then
        XRAY_DOMAIN_PROFILE="$DOMAIN_PROFILE"
    fi
    if [[ -n "$XRAY_DOMAIN_PROFILE" ]] && is_legacy_global_profile_alias "$XRAY_DOMAIN_PROFILE"; then
        log WARN "Профиль ${XRAY_DOMAIN_PROFILE} является legacy-алиасом; используйте global-50 или global-50-auto"
    fi
    if [[ -n "$XRAY_DOMAIN_TIER" ]] && is_legacy_global_profile_alias "$XRAY_DOMAIN_TIER"; then
        log WARN "Профиль ${XRAY_DOMAIN_TIER} является legacy-алиасом; используйте global-50 или global-50-auto"
    fi

    if [[ "$action_is_add" == "true" ]]; then
        local current_tier requested_tier="" raw_current_tier
        raw_current_tier="${DOMAIN_TIER:-tier_ru}"
        current_tier="$raw_current_tier"
        if ! current_tier=$(normalize_domain_tier "$raw_current_tier"); then
            log WARN "Некорректный DOMAIN_TIER в окружении: ${raw_current_tier} (используем tier_ru)"
            current_tier="tier_ru"
        fi

        if [[ -n "$XRAY_DOMAIN_PROFILE" ]]; then
            if ! requested_tier=$(normalize_domain_tier "$XRAY_DOMAIN_PROFILE"); then
                requested_tier="__invalid__"
            fi
        elif [[ -n "$XRAY_DOMAIN_TIER" ]]; then
            if ! requested_tier=$(normalize_domain_tier "$XRAY_DOMAIN_TIER"); then
                requested_tier="__invalid__"
            fi
        fi

        if [[ -n "$requested_tier" ]]; then
            if [[ "$requested_tier" == "__invalid__" ]]; then
                log WARN "Для ${ACTION} указан некорректный --domain-profile/--domain-tier; используется установленный профиль (${current_tier})"
            elif [[ "$requested_tier" != "$current_tier" ]]; then
                log WARN "Для ${ACTION} --domain-profile/--domain-tier игнорируются; используется установленный профиль (${current_tier})"
            fi
        fi

        DOMAIN_TIER="$current_tier"
        AUTO_PROFILE_MODE=false
    else
        if [[ -n "$XRAY_DOMAIN_PROFILE" ]]; then
            if is_auto_domain_profile_alias "$XRAY_DOMAIN_PROFILE"; then
                AUTO_PROFILE_MODE=true
            fi
            if ! DOMAIN_TIER=$(normalize_domain_tier "$XRAY_DOMAIN_PROFILE"); then
                log WARN "Неверный XRAY_DOMAIN_PROFILE: ${XRAY_DOMAIN_PROFILE} (используем tier_ru)"
                DOMAIN_TIER="tier_ru"
            fi
        elif [[ -n "$XRAY_DOMAIN_TIER" ]]; then
            if is_auto_domain_profile_alias "$XRAY_DOMAIN_TIER"; then
                AUTO_PROFILE_MODE=true
            fi
            if ! DOMAIN_TIER=$(normalize_domain_tier "$XRAY_DOMAIN_TIER"); then
                DOMAIN_TIER="$XRAY_DOMAIN_TIER"
            fi
        fi
    fi
    if [[ -n "$XRAY_NUM_CONFIGS" ]]; then
        NUM_CONFIGS="$XRAY_NUM_CONFIGS"
    fi
    if [[ -n "$XRAY_SPIDER_MODE" ]]; then
        SPIDER_MODE=$(parse_bool "$XRAY_SPIDER_MODE" true)
    fi
    if [[ -n "$XRAY_START_PORT" ]]; then
        START_PORT="$XRAY_START_PORT"
    fi
    if [[ -n "$XRAY_TRANSPORT" ]]; then
        TRANSPORT="$XRAY_TRANSPORT"
    fi
    TRANSPORT="${TRANSPORT,,}"
    ADVANCED_MODE=$(parse_bool "${XRAY_ADVANCED:-${ADVANCED_MODE:-false}}" false)
    MUX_MODE="${MUX_MODE,,}"
    QR_ENABLED="${QR_ENABLED,,}"

    if [[ -n "$XRAY_DATA_DIR" ]]; then
        if [[ -z "$XRAY_TIERS_FILE" || "$XRAY_TIERS_FILE" == "$DEFAULT_DATA_DIR/domains.tiers" ]]; then
            XRAY_TIERS_FILE="$XRAY_DATA_DIR/domains.tiers"
        fi
        if [[ -z "$XRAY_SNI_POOLS_FILE" || "$XRAY_SNI_POOLS_FILE" == "$DEFAULT_DATA_DIR/sni_pools.map" ]]; then
            XRAY_SNI_POOLS_FILE="$XRAY_DATA_DIR/sni_pools.map"
        fi
        if [[ -z "$XRAY_GRPC_SERVICES_FILE" || "$XRAY_GRPC_SERVICES_FILE" == "$DEFAULT_DATA_DIR/grpc_services.map" ]]; then
            XRAY_GRPC_SERVICES_FILE="$XRAY_DATA_DIR/grpc_services.map"
        fi
    fi
}
