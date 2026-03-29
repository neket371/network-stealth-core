#!/usr/bin/env bash
# shellcheck shell=bash

ROOT_MODULE_DIR="${MODULE_DIR:-${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}"

GLOBAL_CONTRACT_MODULE="${ROOT_MODULE_DIR}/modules/lib/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

INSTALL_BOOTSTRAP_MODULE="$ROOT_MODULE_DIR/modules/install/bootstrap.sh"
if [[ ! -f "$INSTALL_BOOTSTRAP_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    INSTALL_BOOTSTRAP_MODULE="$XRAY_DATA_DIR/modules/install/bootstrap.sh"
fi
if [[ ! -f "$INSTALL_BOOTSTRAP_MODULE" ]]; then
    log ERROR "Не найден модуль bootstrap-логики: $INSTALL_BOOTSTRAP_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$INSTALL_BOOTSTRAP_MODULE"

INSTALL_OUTPUT_MODULE="$ROOT_MODULE_DIR/modules/install/output.sh"
if [[ ! -f "$INSTALL_OUTPUT_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    INSTALL_OUTPUT_MODULE="$XRAY_DATA_DIR/modules/install/output.sh"
fi
if [[ ! -f "$INSTALL_OUTPUT_MODULE" ]]; then
    log ERROR "Не найден модуль install output: $INSTALL_OUTPUT_MODULE"
    exit 1
fi
# shellcheck source=modules/install/output.sh
source "$INSTALL_OUTPUT_MODULE"

INSTALL_XRAY_RUNTIME_MODULE="$ROOT_MODULE_DIR/modules/install/xray_runtime.sh"
if [[ ! -f "$INSTALL_XRAY_RUNTIME_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    INSTALL_XRAY_RUNTIME_MODULE="$XRAY_DATA_DIR/modules/install/xray_runtime.sh"
fi
if [[ ! -f "$INSTALL_XRAY_RUNTIME_MODULE" ]]; then
    log ERROR "Не найден модуль install xray runtime: $INSTALL_XRAY_RUNTIME_MODULE"
    exit 1
fi
# shellcheck source=modules/install/xray_runtime.sh
source "$INSTALL_XRAY_RUNTIME_MODULE"

INSTALL_SELECTION_MODULE="$ROOT_MODULE_DIR/modules/install/selection.sh"
if [[ ! -f "$INSTALL_SELECTION_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    INSTALL_SELECTION_MODULE="$XRAY_DATA_DIR/modules/install/selection.sh"
fi
if [[ ! -f "$INSTALL_SELECTION_MODULE" ]]; then
    log ERROR "Не найден модуль install selection: $INSTALL_SELECTION_MODULE"
    exit 1
fi
# shellcheck source=modules/install/selection.sh
source "$INSTALL_SELECTION_MODULE"

OPERATOR_DECISION_MODULE="$ROOT_MODULE_DIR/modules/health/operator_decision.sh"
if [[ ! -f "$OPERATOR_DECISION_MODULE" && "${XRAY_SOURCE_TREE_STRICT:-false}" != "true" && -n "${XRAY_DATA_DIR:-}" ]]; then
    OPERATOR_DECISION_MODULE="$XRAY_DATA_DIR/modules/health/operator_decision.sh"
fi
if [[ ! -f "$OPERATOR_DECISION_MODULE" ]]; then
    log ERROR "Не найден модуль operator decision: $OPERATOR_DECISION_MODULE"
    exit 1
fi
# shellcheck source=modules/health/operator_decision.sh
source "$OPERATOR_DECISION_MODULE"

optimize_system() {
    log STEP "Оптимизируем систему..."

    backup_file /etc/sysctl.d/99-xray.conf
    atomic_write /etc/sysctl.d/99-xray.conf 0644 << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.netfilter.nf_conntrack_max = 1048576
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
fs.file-max = 1000000
EOF

    local sysctl_err=""
    if ! sysctl_err=$(sysctl -e -p /etc/sysctl.d/99-xray.conf 2>&1); then
        if [[ "$sysctl_err" =~ [Pp]ermission[[:space:]]denied|[Oo]peration[[:space:]]not[[:space:]]permitted|[Rr]ead-only[[:space:]]file[[:space:]]system ]]; then
            log INFO "Часть sysctl-параметров недоступна в текущей среде (виртуализация/контейнер)"
            debug_file "sysctl apply constraints: $(echo "$sysctl_err" | tr '\n' ';')"
        else
            log WARN "Не удалось полностью применить sysctl; детали сохранены в debug log"
            debug_file "sysctl apply failed: $(echo "$sysctl_err" | tr '\n' ';')"
        fi
    fi

    backup_file /etc/security/limits.d/99-xray.conf
    atomic_write /etc/security/limits.d/99-xray.conf 0644 << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
EOF

    log OK "BBR и оптимизации применены"
}

create_users() {
    log STEP "Создаём непривилегированных пользователей..."

    if ! getent group "$XRAY_GROUP" > /dev/null 2>&1; then
        groupadd -r "$XRAY_GROUP"
        log OK "Группа ${XRAY_GROUP} создана"
    else
        log INFO "Группа ${XRAY_GROUP} уже существует"
    fi
    if ! id "$XRAY_USER" > /dev/null 2>&1; then
        useradd -r -g "$XRAY_GROUP" -s /usr/sbin/nologin -d "$XRAY_HOME" -M "$XRAY_USER"
        log OK "Пользователь ${XRAY_USER} создан"
    else
        log INFO "Пользователь ${XRAY_USER} уже существует"
    fi

    mkdir -p "$XRAY_HOME" "$XRAY_BACKUP" /etc/xray/private /etc/xray-reality
    chown -R "${XRAY_USER}:${XRAY_GROUP}" "$XRAY_HOME"
    if declare -F ensure_xray_runtime_logs_ready > /dev/null 2>&1; then
        ensure_xray_runtime_logs_ready
    else
        mkdir -p "$XRAY_LOGS"
        chown -R "${XRAY_USER}:${XRAY_GROUP}" "$XRAY_LOGS"
        chmod 750 "$XRAY_LOGS"
        touch "$XRAY_LOGS/access.log" "$XRAY_LOGS/error.log"
        chown "${XRAY_USER}:${XRAY_GROUP}" "$XRAY_LOGS/access.log" "$XRAY_LOGS/error.log"
        chmod 640 "$XRAY_LOGS/access.log" "$XRAY_LOGS/error.log"
    fi
    chown root:root "$XRAY_BACKUP"
    chmod 700 "$XRAY_BACKUP"
    chmod 750 /etc/xray/private
    chown "root:${XRAY_GROUP}" /etc/xray/private
}

detect_ips() {
    log STEP "Определяем IP-адреса сервера..."

    if [[ -z "${SERVER_IP:-}" ]]; then
        SERVER_IP=$(fetch_ip 4 || true)
    else
        log INFO "IPv4 задан заранее: ${SERVER_IP}"
    fi
    if [[ -z "$SERVER_IP" ]]; then
        log ERROR "Не удалось определить IPv4 автоматически. Укажите SERVER_IP или --server-ip."
        exit 1
    fi

    if ! is_valid_ipv4 "$SERVER_IP"; then
        log ERROR "Некорректный IPv4 адрес: $SERVER_IP"
        log INFO "Подсказка: используйте формат X.X.X.X (например: 185.100.50.25)"
        exit 1
    fi

    log OK "IPv4: ${BOLD}${SERVER_IP}${NC}"

    if [[ -z "${SERVER_IP6:-}" ]]; then
        SERVER_IP6=$(fetch_ip 6 || true)
    else
        log INFO "IPv6 задан заранее: ${SERVER_IP6}"
    fi

    if [[ -n "$SERVER_IP6" ]]; then
        if is_valid_ipv6 "$SERVER_IP6"; then
            log OK "IPv6: ${BOLD}${SERVER_IP6}${NC}"
            HAS_IPV6=true
        else
            log WARN "Авто-детект вернул невалидный IPv6: ${SERVER_IP6} (IPv6 отключён)"
            SERVER_IP6=""
            HAS_IPV6=false
        fi
    else
        log INFO "IPv6 недоступен"
        HAS_IPV6=false
    fi
    : "${HAS_IPV6}"

    echo ""
}

install_flow() {
    INSTALL_START_TIME=$(date +%s)
    LOG_CONTEXT="установки"
    : "${LOG_CONTEXT}"
    setup_logging
    resolve_paths
    detect_distro
    check_disk_space
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl

    require_cmd unzip
    install_self
    setup_logrotate
    optimize_system
    create_users
    install_minisign
    install_xray
    maybe_reuse_existing_config || true
    ask_domain_profile
    ask_num_configs
    detect_ips
    auto_configure
    setup_domains
    allocate_ports
    generate_keys
    build_config
    create_systemd_service
    setup_diagnose_service
    configure_firewall
    save_environment
    save_policy_file || log WARN "Не удалось сохранить policy.json"
    setup_health_monitoring
    setup_auto_update
    save_client_configs
    if declare -F export_all_configs > /dev/null 2>&1; then
        export_all_configs
    else
        log WARN "Модуль export.sh не загружен; экспорт клиентских конфигов и canary bundle пропущен"
    fi
    ensure_self_check_artifacts_ready
    if ! verify_ports_available; then
        log ERROR "Некоторые порты заняты. Перезапустите установку."
        exit 1
    fi
    start_services
    if ! verify_ports_listening_after_start; then
        log ERROR "Проверка listening-портов после запуска не пройдена."
        exit 1
    fi
    test_reality_connectivity
    log STEP "Запускаем transport-aware self-check..."
    if ! post_action_verdict "install"; then
        log ERROR "Финальная self-check (install) завершилась с verdict=BROKEN"
        exit 1
    fi
    show_install_result
}

move_runtime_array_index_to_front() {
    local index="$1"
    local array_name="$2"
    # shellcheck disable=SC2034 # nameref target is the point of the helper.
    local -n array_ref="$array_name"
    if [[ ! "$index" =~ ^[0-9]+$ ]] || ((index < 0 || index >= ${#array_ref[@]})); then
        return 1
    fi
    if ((${#array_ref[@]} < 2 || index == 0)); then
        return 0
    fi

    local -a reordered=("${array_ref[$index]}")
    local i
    for ((i = 0; i < ${#array_ref[@]}; i++)); do
        ((i == index)) && continue
        reordered+=("${array_ref[$i]}")
    done
    array_ref=("${reordered[@]}")
}

reorder_runtime_arrays_to_primary_index() {
    local index="$1"
    local name
    for name in PORTS PORTS_V6 UUIDS SHORT_IDS PRIVATE_KEYS PUBLIC_KEYS CONFIG_DOMAINS CONFIG_DESTS CONFIG_SNIS CONFIG_FPS CONFIG_TRANSPORT_ENDPOINTS CONFIG_PROVIDER_FAMILIES CONFIG_VLESS_ENCRYPTIONS CONFIG_VLESS_DECRYPTIONS; do
        if declare -p "$name" > /dev/null 2>&1; then
            # Optional arrays like PORTS_V6 can be legitimately empty.
            local -n _reorder_array_ref="$name"
            ((${#_reorder_array_ref[@]} == 0)) && continue
            move_runtime_array_index_to_front "$index" "$name" || return 1
        fi
    done
    return 0
}

runtime_config_name_at_index() {
    local index="${1:-0}"
    local json_file="${XRAY_KEYS}/clients.json"
    if [[ -f "$json_file" ]]; then
        jq -r --argjson idx "$index" '.configs[$idx].name // empty' "$json_file" 2> /dev/null || true
        return 0
    fi
    printf 'Config %s\n' "$((index + 1))"
}

runtime_config_index_by_name() {
    local config_name="$1"
    local json_file="${XRAY_KEYS}/clients.json"
    if [[ -f "$json_file" ]]; then
        jq -r --arg name "$config_name" '.configs | map(.name) | index($name) // empty' "$json_file" 2> /dev/null || true
        return 0
    fi
    if [[ "$config_name" =~ ^Config[[:space:]]+([0-9]+)$ ]]; then
        printf '%s\n' "$((BASH_REMATCH[1] - 1))"
    fi
}

maybe_promote_runtime_primary_from_observations() {
    if ((NUM_CONFIGS < 2)); then
        return 1
    fi

    local current_primary decision_json candidate_name candidate_reason promotion_block_reason
    current_primary=$(runtime_config_name_at_index 0)
    decision_json=$(operator_rotation_apply_observations "${ACTION:-runtime-mutation}" 2> /dev/null || true)
    [[ -n "$decision_json" ]] || return 1

    candidate_name=$(jq -r '.promotion_name // empty' <<< "$decision_json" 2> /dev/null || true)
    candidate_reason=$(jq -r '.promotion_reason // empty' <<< "$decision_json" 2> /dev/null || true)
    promotion_block_reason=$(jq -r '.promotion_block_reason // empty' <<< "$decision_json" 2> /dev/null || true)

    if ! jq -e '.should_promote == true' <<< "$decision_json" > /dev/null 2>&1; then
        [[ -n "$promotion_block_reason" ]] && log INFO "Rotation удержана: ${promotion_block_reason}"
        return 1
    fi

    [[ -n "$candidate_name" ]] || return 1
    [[ "$candidate_name" != "$current_primary" ]] || return 1

    local candidate_index
    candidate_index=$(runtime_config_index_by_name "$candidate_name")
    [[ "$candidate_index" =~ ^[0-9]+$ ]] || return 1
    reorder_runtime_arrays_to_primary_index "$candidate_index" || return 1
    log INFO "Primary client order обновлён: ${candidate_name}"
    [[ -n "$candidate_reason" ]] && log INFO "Причина promotion: ${candidate_reason}"
    return 0
}

update_flow() {
    LOG_CONTEXT="обновления"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="$UPDATE_LOG"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl

    require_cmd unzip
    install_self
    setup_logrotate
    update_xray
    if [[ -f "$XRAY_CONFIG" ]]; then
        load_existing_ports_from_config
        load_existing_metadata_from_config
        load_keys_from_config
        NUM_CONFIGS=${#PORTS[@]}
        if ((NUM_CONFIGS > 0)) && build_public_keys_for_current_config; then
            if [[ "${REPLAN:-false}" == "true" ]]; then
                maybe_promote_runtime_primary_from_observations || true
            fi
            rebuild_client_artifacts_from_loaded_state || exit 1
            save_environment || log WARN "Не удалось обновить окружение после update"
            save_policy_file || log WARN "Не удалось обновить policy.json после update"
            if ! verify_ports_listening_after_start; then
                log ERROR "Проверка listening-портов после update не пройдена."
                exit 1
            fi
            test_reality_connectivity || true
        fi
    fi
    ensure_self_check_artifacts_ready
    setup_diagnose_service
    setup_auto_update
    if ! post_action_verdict "update"; then
        log ERROR "Финальная self-check (update) завершилась с verdict=BROKEN"
        exit 1
    fi
    log OK "Обновление завершено"
}

repair_flow() {
    LOG_CONTEXT="восстановления"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="/var/log/xray-repair.log"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl
    require_cmd unzip

    install_self
    setup_logrotate
    create_users
    install_minisign

    if [[ ! -x "$XRAY_BIN" ]]; then
        log WARN "Бинарник Xray не найден; устанавливаем заново"
        install_xray
    fi

    local config_ready=false
    if [[ -f "$XRAY_CONFIG" ]]; then
        if ! jq empty "$XRAY_CONFIG" > /dev/null 2>&1; then
            log ERROR "Найденный config.json повреждён (невалидный JSON)"
            exit 1
        fi
        if ! xray_config_test_ok "$XRAY_CONFIG"; then
            log ERROR "Текущий config.json не проходит xray -test"
            exit 1
        fi
        config_ready=true
    else
        log WARN "Конфигурация Xray не найдена: ${XRAY_CONFIG}"
    fi

    create_systemd_service
    setup_diagnose_service

    if [[ "$config_ready" == "true" ]]; then
        load_existing_ports_from_config
        load_existing_metadata_from_config
        load_keys_from_config
        build_public_keys_for_current_config || exit 1
        maybe_promote_runtime_primary_from_observations || true
        if ((${#PORTS[@]} > 0)); then
            configure_firewall
        else
            log WARN "В config.json нет inbounds для восстановления правил firewall"
        fi
    fi

    setup_health_monitoring
    setup_auto_update

    local repair_artifacts_degraded=false

    if [[ "$config_ready" == "true" ]]; then
        start_services
        if ((${#PORTS[@]} > 0)); then
            if ! verify_ports_listening_after_start; then
                log WARN "После repair часть портов не слушается"
            fi
            test_reality_connectivity || true
        fi
        if ! rebuild_client_artifacts_from_loaded_state; then
            log ERROR "Не удалось полностью восстановить клиентские артефакты"
            repair_artifacts_degraded=true
        fi
        if ! ensure_self_check_artifacts_ready; then
            log ERROR "Не удалось полностью подготовить self-check артефакты"
            repair_artifacts_degraded=true
        fi

        NUM_CONFIGS=${#PORTS[@]}
        if ((NUM_CONFIGS > 0)); then
            START_PORT="${PORTS[0]}"
        fi
        if [[ -z "${SERVER_IP:-}" ]]; then
            SERVER_IP=$(fetch_ip 4 || true)
        fi
        if [[ -z "${SERVER_IP6:-}" ]]; then
            SERVER_IP6=$(fetch_ip 6 || true)
        fi
        save_environment || log WARN "Не удалось обновить окружение после repair"
        save_policy_file || log WARN "Не удалось обновить policy.json после repair"
    fi

    if [[ "$repair_artifacts_degraded" == "true" ]]; then
        log ERROR "Восстановление завершилось с деградированными клиентскими или self-check артефактами"
        exit 1
    fi

    if ! post_action_verdict "repair"; then
        log ERROR "Финальная self-check (repair) завершилась с verdict=BROKEN"
        exit 1
    fi

    log OK "Восстановление завершено"
}

migrate_stealth_flow() {
    LOG_CONTEXT="миграции transport"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="/var/log/xray-migrate-stealth.log"
    : "${INSTALL_LOG}"
    setup_logging
    resolve_paths
    detect_distro
    install_dependencies
    require_cmd curl
    require_cmd jq
    require_cmd openssl
    require_cmd unzip

    install_self
    setup_logrotate
    create_users
    install_minisign

    if [[ -x "$XRAY_BIN" ]]; then
        update_xray
    else
        install_xray
    fi

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        log ERROR "Конфигурация Xray не найдена: ${XRAY_CONFIG}"
        exit 1
    fi
    if ! jq empty "$XRAY_CONFIG" > /dev/null 2>&1; then
        log ERROR "config.json повреждён (невалидный JSON)"
        exit 1
    fi
    if ! xray_config_test_ok "$XRAY_CONFIG"; then
        log ERROR "Текущий config.json не проходит xray -test"
        exit 1
    fi

    load_existing_ports_from_config
    load_existing_metadata_from_config
    load_keys_from_config
    NUM_CONFIGS=${#PORTS[@]}
    if ((NUM_CONFIGS < 1)); then
        log ERROR "Не найдены managed reality inbounds для миграции"
        exit 1
    fi
    if ! build_public_keys_for_current_config; then
        exit 1
    fi

    if [[ -z "${SERVER_IP:-}" ]]; then
        detect_ips
    fi

    MUX_MODE="off"
    local needs_contract_refresh=false
    if jq -e --arg flow "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}" '
        [ .inbounds[]
          | select(.streamSettings.realitySettings != null)
          | select((.listen // "0.0.0.0") | test(":") | not)
          | ((.settings.decryption // "none") != "none")
            and ((.settings.clients[0].flow // "") == $flow)
        ] | all
    ' "$XRAY_CONFIG" > /dev/null 2>&1; then
        needs_contract_refresh=false
    else
        needs_contract_refresh=true
    fi

    if [[ "${TRANSPORT:-xhttp}" == "xhttp" && "$needs_contract_refresh" == false ]]; then
        log INFO "Managed transport уже использует strongest direct stack; обновляем только артефакты и окружение"
    else
        if [[ "${TRANSPORT:-xhttp}" == "xhttp" ]]; then
            log WARN "Обнаружен xhttp без strongest direct contract; обновляем decryption/flow"
        else
            log WARN "Обнаружен legacy transport (${TRANSPORT}); выполняем миграцию на xhttp"
        fi
        if ! rebuild_config_for_transport "xhttp"; then
            log ERROR "Не удалось пересобрать config.json под xhttp"
            exit 1
        fi
    fi

    create_systemd_service
    setup_diagnose_service
    configure_firewall
    setup_health_monitoring
    setup_auto_update
    save_environment
    save_policy_file || log WARN "Не удалось сохранить policy.json после migrate-stealth"
    start_services
    if ! verify_ports_listening_after_start; then
        log ERROR "Проверка listening-портов после migrate-stealth не пройдена."
        exit 1
    fi
    test_reality_connectivity
    rebuild_client_artifacts_from_config || exit 1
    ensure_self_check_artifacts_ready || exit 1
    if ! post_action_verdict "migrate-stealth"; then
        log ERROR "Финальная self-check (migrate-stealth) завершилась с verdict=BROKEN"
        exit 1
    fi
    log OK "Миграция на xhttp завершена"
}

diagnose_flow() {
    LOG_CONTEXT="диагностики"
    : "${LOG_CONTEXT}"
    INSTALL_LOG="$DIAG_LOG"
    : "${INSTALL_LOG}"
    setup_logging
    diagnose
}

rollback_flow() {
    LOG_CONTEXT="отката"
    : "${LOG_CONTEXT}"
    setup_logging
    rollback_from_session "$ROLLBACK_DIR"
}

uninstall_flow() {
    LOG_CONTEXT="удаления"
    : "${LOG_CONTEXT}"
    if ! uninstall_has_managed_artifacts; then
        echo ""
        log INFO "Network Stealth Core уже удалён: управляемые артефакты не обнаружены"
        return 0
    fi
    setup_logging
    uninstall_all
}
