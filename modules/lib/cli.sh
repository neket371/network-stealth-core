#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # Writes shared globals used by sourced runtime modules.

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

cli_is_action() {
    local value="${1:-}"
    case "$value" in
        install | add-clients | add-keys | update | repair | migrate-stealth | diagnose | doctor | rollback | uninstall | status | logs | check-update)
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
            --tiers-file | --sni-pools-file | --transport-endpoints-file | --grpc-services-file | --start-port | --server-ip | --server-ip6 | --mux-mode | \
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
    local next_value="${!OPTIND:-}"
    if [[ -z "$next_value" || "$next_value" == --* || ("$next_value" == -* && "$next_value" != "-") ]]; then
        log ERROR "Не указан параметр для --${optarg}"
        exit 1
    fi
    printf '%s' "$next_value"
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

cli_handle_long_option_flag() {
    local optarg="$1"

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
            return 0
            ;;
        verbose)
            VERBOSE=true
            return 0
            ;;
        allow-insecure-sha256)
            ALLOW_INSECURE_SHA256=true
            return 0
            ;;
        require-minisign)
            REQUIRE_MINISIGN=true
            return 0
            ;;
        no-require-minisign)
            REQUIRE_MINISIGN=false
            return 0
            ;;
        allow-no-systemd)
            ALLOW_NO_SYSTEMD=true
            return 0
            ;;
        no-allow-no-systemd)
            ALLOW_NO_SYSTEMD=false
            return 0
            ;;
        spider | spider-mode)
            XRAY_SPIDER_MODE="true"
            return 0
            ;;
        no-spider)
            XRAY_SPIDER_MODE="false"
            return 0
            ;;
        domain-check)
            DOMAIN_CHECK="true"
            return 0
            ;;
        no-domain-check)
            DOMAIN_CHECK="false"
            return 0
            ;;
        skip-reality-check)
            SKIP_REALITY_CHECK="true"
            return 0
            ;;
        keep-local-backups)
            KEEP_LOCAL_BACKUPS="true"
            return 0
            ;;
        no-local-backups)
            KEEP_LOCAL_BACKUPS="false"
            return 0
            ;;
        reuse-config)
            REUSE_EXISTING="true"
            return 0
            ;;
        no-reuse-config)
            REUSE_EXISTING="false"
            return 0
            ;;
        auto-rollback)
            AUTO_ROLLBACK="true"
            return 0
            ;;
        no-auto-rollback)
            AUTO_ROLLBACK="false"
            return 0
            ;;
        qr)
            QR_ENABLED="true"
            return 0
            ;;
        no-qr)
            QR_ENABLED="false"
            return 0
            ;;
        auto-update)
            AUTO_UPDATE="true"
            return 0
            ;;
        no-auto-update)
            AUTO_UPDATE="false"
            return 0
            ;;
        replan)
            REPLAN="true"
            return 0
            ;;
        no-replan)
            REPLAN="false"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

cli_handle_long_option_value() {
    local optarg="$1"
    local value

    case "$optarg" in
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
        transport-endpoints-file | transport-endpoints-file=*)
            XRAY_TRANSPORT_ENDPOINTS_FILE="$(cli_read_long_option_value "$optarg")"
            ;;
        grpc-services-file | grpc-services-file=*)
            XRAY_GRPC_SERVICES_FILE="$(cli_read_long_option_value "$optarg")"
            XRAY_TRANSPORT_ENDPOINTS_FILE="$XRAY_GRPC_SERVICES_FILE"
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
        auto-update-oncalendar | auto-update-oncalendar=*)
            AUTO_UPDATE_ONCALENDAR="$(cli_read_long_option_value "$optarg")"
            ;;
        auto-update-random-delay | auto-update-random-delay=*)
            AUTO_UPDATE_RANDOM_DELAY="$(cli_read_long_option_value "$optarg")"
            ;;
        *)
            return 1
            ;;
    esac
}

cli_handle_long_option_action() {
    local optarg="$1"

    case "$optarg" in
        rollback | rollback=*)
            ACTION="rollback"
            if [[ "$optarg" == *=* ]]; then
                ROLLBACK_DIR="${optarg#*=}"
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
        doctor)
            ACTION="doctor"
            ;;
        *)
            return 1
            ;;
    esac
}

cli_handle_long_option() {
    local optarg="$1"

    if cli_handle_long_option_flag "$optarg"; then
        return 0
    fi
    if cli_handle_long_option_value "$optarg"; then
        return 0
    fi
    if cli_handle_long_option_action "$optarg"; then
        return 0
    fi

    log ERROR "Неизвестный аргумент: --$optarg"
    print_usage
    exit 1
}

parse_args_collect_tokens() {
    local -n out_opts="$1"
    local -n out_pos="$2"
    local -n out_cmd="$3"
    local -n out_explicit_cmd="$4"
    shift 4
    local args=("$@")
    local i=0

    while [[ $i -lt ${#args[@]} ]]; do
        local a="${args[$i]}"

        if [[ "$a" == "--" ]]; then
            i=$((i + 1))
            while [[ $i -lt ${#args[@]} ]]; do
                out_pos+=("${args[$i]}")
                i=$((i + 1))
            done
            break
        fi

        if [[ -z "$out_cmd" ]] && cli_is_action "$a"; then
            out_cmd="$a"
            out_explicit_cmd="$a"
            i=$((i + 1))
            continue
        fi

        if [[ "$a" == --* || "$a" == -* ]]; then
            if cli_option_requires_value "$a" && [[ "$a" != *=* ]]; then
                i=$((i + 1))
                if [[ $i -ge ${#args[@]} ]]; then
                    log ERROR "Не указан параметр для $a"
                    exit 1
                fi
                local next_value="${args[$i]}"
                if [[ "$next_value" == --* || ("$next_value" == -* && "$next_value" != "-") ]]; then
                    log ERROR "Не указан параметр для $a"
                    exit 1
                fi
                out_opts+=("${a}=${next_value}")
            elif [[ "$a" == --rollback && "$a" != *=* ]]; then
                local next="${args[$((i + 1))]:-}"
                if [[ -n "$next" && "$next" != --* && "$next" != -* ]]; then
                    i=$((i + 1))
                    out_opts+=("${a}=${next}")
                else
                    out_opts+=("$a")
                fi
            else
                out_opts+=("$a")
            fi
        else
            out_pos+=("$a")
        fi

        i=$((i + 1))
    done
}

parse_args_validate_remaining() {
    local -n remaining_args="$1"

    if ((${#remaining_args[@]} > 0)); then
        log ERROR "Неожиданные аргументы после разбора опций: ${remaining_args[*]}"
        print_usage
        exit 1
    fi
}

parse_args_apply_action_positionals() {
    local -n positional_args="$1"

    case "$ACTION" in
        rollback)
            if [[ -z "$ROLLBACK_DIR" && ${#positional_args[@]} -gt 0 && "${positional_args[0]}" != --* ]]; then
                ROLLBACK_DIR="${positional_args[0]}"
                positional_args=("${positional_args[@]:1}")
            fi
            ;;
        logs)
            if [[ ${#positional_args[@]} -gt 0 && "${positional_args[0]}" != --* ]]; then
                # shellcheck disable=SC2034 # Used in health.sh
                LOGS_TARGET="${positional_args[0]}"
                positional_args=("${positional_args[@]:1}")
            fi
            ;;
        add-clients | add-keys)
            if [[ ${#positional_args[@]} -gt 0 && "${positional_args[0]}" != --* ]]; then
                # shellcheck disable=SC2034 # Used in config.sh add_clients_flow
                ADD_CLIENTS_COUNT="${positional_args[0]}"
                positional_args=("${positional_args[@]:1}")
            fi
            ;;
        *) ;;
    esac
}

parse_args() {
    local cmd=""
    local explicit_cmd=""
    local opts=()
    local pos=()
    local remaining=()

    parse_args_collect_tokens opts pos cmd explicit_cmd "$@"

    set -- "${opts[@]}"

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

    shift $((OPTIND - 1)) || true
    if [[ $# -gt 0 ]]; then
        remaining=("$@")
    fi
    parse_args_validate_remaining remaining

    if [[ -n "$cmd" ]]; then
        ACTION="$cmd"
    fi

    if [[ -z "$explicit_cmd" && ${#pos[@]} -gt 0 ]]; then
        log ERROR "Неизвестная команда: ${pos[0]}"
        print_usage
        exit 1
    fi

    parse_args_apply_action_positionals pos

    if ((${#pos[@]} > 0)); then
        log ERROR "Неожиданные позиционные аргументы для '${ACTION}': ${pos[*]}"
        print_usage
        exit 1
    fi
}

apply_runtime_overrides_normalize_flags() {
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
    SELF_CHECK_ENABLED=$(parse_bool "$SELF_CHECK_ENABLED" true)
    normalize_progress_mode
    normalize_runtime_common_ranges
    normalize_runtime_schedule_settings
    normalize_primary_domain_controls
}

apply_runtime_overrides_seed_runtime_defaults() {
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
    if [[ -z "${SELF_CHECK_URLS:-}" ]]; then
        SELF_CHECK_URLS="https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204"
    fi
    if [[ -z "${SELF_CHECK_STATE_FILE:-}" ]]; then
        SELF_CHECK_STATE_FILE="/var/lib/xray/self-check.json"
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
}

apply_runtime_overrides_resolve_domain_selection() {
    local action_is_add="${1:-false}"

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
}

apply_runtime_overrides_apply_explicit_env_overrides() {
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
}

apply_runtime_overrides_enforce_transport_contract() {
    TRANSPORT="${TRANSPORT,,}"
    case "${ACTION:-install}" in
        migrate-stealth)
            case "$TRANSPORT" in
                "" | xhttp | grpc | http2) ;;
                h2) TRANSPORT="http2" ;;
                *)
                    log ERROR "Неверный TRANSPORT: ${TRANSPORT} (для migrate-stealth допускаются xhttp|grpc|http2)"
                    exit 1
                    ;;
            esac
            ;;
        status | logs | diagnose | check-update | rollback | uninstall)
            case "$TRANSPORT" in
                "" | xhttp)
                    TRANSPORT="xhttp"
                    ;;
                grpc | http2 | h2)
                    local current_transport=""
                    [[ "$TRANSPORT" == "h2" ]] && TRANSPORT="http2"
                    if managed_install_contract_present; then
                        current_transport="$(detect_current_managed_transport)"
                    fi
                    if ! contract_gate_transport_is_legacy "$current_transport" || [[ "$TRANSPORT" != "$current_transport" ]]; then
                        log ERROR "TRANSPORT=${TRANSPORT} больше не поддерживается в v7; используйте xhttp или migrate-stealth для legacy install"
                        exit 1
                    fi
                    ;;
                *)
                    log ERROR "Неверный TRANSPORT: ${TRANSPORT} (в v7 поддерживается только xhttp)"
                    exit 1
                    ;;
            esac
            ;;
        *)
            case "$TRANSPORT" in
                "" | xhttp)
                    TRANSPORT="xhttp"
                    ;;
                grpc | http2 | h2)
                    log ERROR "TRANSPORT=${TRANSPORT} больше не поддерживается в v7; используйте xhttp или migrate-stealth для legacy install"
                    exit 1
                    ;;
                *)
                    log ERROR "Неверный TRANSPORT: ${TRANSPORT} (в v7 поддерживается только xhttp)"
                    exit 1
                    ;;
            esac
            ;;
    esac
    if [[ -n "${XRAY_TRANSPORT:-}" ]]; then
        XRAY_TRANSPORT="$TRANSPORT"
    fi
}

apply_runtime_overrides_finalize_modes() {
    ADVANCED_MODE=$(parse_bool "${XRAY_ADVANCED:-${ADVANCED_MODE:-false}}" false)
    MUX_MODE="${MUX_MODE,,}"
    QR_ENABLED="${QR_ENABLED,,}"
}

apply_runtime_overrides_rebind_data_paths() {
    if [[ -n "$XRAY_DATA_DIR" ]]; then
        if [[ -z "$XRAY_TIERS_FILE" || "$XRAY_TIERS_FILE" == "$DEFAULT_DATA_DIR/domains.tiers" ]]; then
            XRAY_TIERS_FILE="$XRAY_DATA_DIR/domains.tiers"
        fi
        if [[ -z "$XRAY_SNI_POOLS_FILE" || "$XRAY_SNI_POOLS_FILE" == "$DEFAULT_DATA_DIR/sni_pools.map" ]]; then
            XRAY_SNI_POOLS_FILE="$XRAY_DATA_DIR/sni_pools.map"
        fi
        sync_transport_endpoint_file_contract
    fi
}

apply_runtime_overrides() {
    local action_is_add=false
    AUTO_PROFILE_MODE=false
    if [[ "$ACTION" == "add-clients" || "$ACTION" == "add-keys" ]]; then
        action_is_add=true
    fi

    apply_runtime_overrides_normalize_flags
    apply_runtime_overrides_seed_runtime_defaults
    apply_runtime_overrides_resolve_domain_selection "$action_is_add"
    apply_runtime_overrides_apply_explicit_env_overrides
    apply_runtime_overrides_enforce_transport_contract
    apply_runtime_overrides_finalize_modes
    apply_runtime_overrides_rebind_data_paths
}
