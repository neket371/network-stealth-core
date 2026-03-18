#!/usr/bin/env bash
# shellcheck shell=bash

GLOBAL_CONTRACT_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/lib/globals_contract.sh"
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    GLOBAL_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/lib/globals_contract.sh"
fi
if [[ ! -f "$GLOBAL_CONTRACT_MODULE" ]]; then
    echo "ERROR: не найден модуль global contract: $GLOBAL_CONTRACT_MODULE" >&2
    exit 1
fi
# shellcheck source=modules/lib/globals_contract.sh
source "$GLOBAL_CONTRACT_MODULE"

CONFIG_DOMAIN_MODULE="$SCRIPT_DIR/modules/config/domain_planner.sh"
if [[ ! -f "$CONFIG_DOMAIN_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_DOMAIN_MODULE="$XRAY_DATA_DIR/modules/config/domain_planner.sh"
fi
if [[ ! -f "$CONFIG_DOMAIN_MODULE" ]]; then
    log ERROR "Не найден модуль доменного планировщика: $CONFIG_DOMAIN_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_DOMAIN_MODULE"

CONFIG_SHARED_HELPERS_MODULE="$SCRIPT_DIR/modules/config/shared_helpers.sh"
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_SHARED_HELPERS_MODULE="$XRAY_DATA_DIR/modules/config/shared_helpers.sh"
fi
if [[ ! -f "$CONFIG_SHARED_HELPERS_MODULE" ]]; then
    log ERROR "Не найден модуль общих helper-функций config: $CONFIG_SHARED_HELPERS_MODULE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_SHARED_HELPERS_MODULE"

CONFIG_RUNTIME_CONTRACT_MODULE="$SCRIPT_DIR/modules/config/runtime_contract.sh"
if [[ ! -f "$CONFIG_RUNTIME_CONTRACT_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_RUNTIME_CONTRACT_MODULE="$XRAY_DATA_DIR/modules/config/runtime_contract.sh"
fi
if [[ ! -f "$CONFIG_RUNTIME_CONTRACT_MODULE" ]]; then
    log ERROR "Не найден модуль runtime contract: $CONFIG_RUNTIME_CONTRACT_MODULE"
    exit 1
fi
# shellcheck source=modules/config/runtime_contract.sh
source "$CONFIG_RUNTIME_CONTRACT_MODULE"

CONFIG_RUNTIME_APPLY_MODULE="$SCRIPT_DIR/modules/config/runtime_apply.sh"
if [[ ! -f "$CONFIG_RUNTIME_APPLY_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_RUNTIME_APPLY_MODULE="$XRAY_DATA_DIR/modules/config/runtime_apply.sh"
fi
if [[ ! -f "$CONFIG_RUNTIME_APPLY_MODULE" ]]; then
    log ERROR "Не найден модуль runtime apply: $CONFIG_RUNTIME_APPLY_MODULE"
    exit 1
fi
# shellcheck source=modules/config/runtime_apply.sh
source "$CONFIG_RUNTIME_APPLY_MODULE"

CONFIG_CLIENT_ARTIFACTS_MODULE="$SCRIPT_DIR/modules/config/client_artifacts.sh"
if [[ ! -f "$CONFIG_CLIENT_ARTIFACTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_CLIENT_ARTIFACTS_MODULE="$XRAY_DATA_DIR/modules/config/client_artifacts.sh"
fi
if [[ ! -f "$CONFIG_CLIENT_ARTIFACTS_MODULE" ]]; then
    log ERROR "Не найден модуль client artifacts: $CONFIG_CLIENT_ARTIFACTS_MODULE"
    exit 1
fi
# shellcheck source=modules/config/client_artifacts.sh
source "$CONFIG_CLIENT_ARTIFACTS_MODULE"

CONFIG_ADD_CLIENTS_MODULE="$SCRIPT_DIR/modules/config/add_clients.sh"
if [[ ! -f "$CONFIG_ADD_CLIENTS_MODULE" && -n "${XRAY_DATA_DIR:-}" ]]; then
    CONFIG_ADD_CLIENTS_MODULE="$XRAY_DATA_DIR/modules/config/add_clients.sh"
fi
if [[ ! -f "$CONFIG_ADD_CLIENTS_MODULE" ]]; then
    log ERROR "Не найден модуль add-clients: $CONFIG_ADD_CLIENTS_MODULE"
    exit 1
fi
# shellcheck source=modules/config/add_clients.sh
source "$CONFIG_ADD_CLIENTS_MODULE"

build_config() {
    log STEP "Собираем конфигурацию Xray (modular)..."

    if [[ "$REUSE_EXISTING_CONFIG" == true ]]; then
        log INFO "Конфигурация не пересоздаётся (используем текущую)"
        return 0
    fi

    local inbounds='[]'
    # shellcheck disable=SC2034 # Used via nameref in pick_random_from_array.
    local -a fp_pool=("chrome" "chrome" "chrome" "firefox" "chrome" "firefox")

    CONFIG_DOMAINS=()
    CONFIG_SNIS=()
    CONFIG_TRANSPORT_ENDPOINTS=()
    CONFIG_DESTS=()
    CONFIG_FPS=()
    CONFIG_PROVIDER_FAMILIES=()
    CONFIG_VLESS_ENCRYPTIONS=()
    CONFIG_VLESS_DECRYPTIONS=()

    setup_mux_settings
    check_xray_version_for_config_generation
    ensure_xray_feature_contract

    if [[ ${#PORTS[@]} -lt $NUM_CONFIGS ]]; then
        log ERROR "Массив портов (${#PORTS[@]}) меньше NUM_CONFIGS ($NUM_CONFIGS)"
        exit 1
    fi
    if [[ ${#UUIDS[@]} -lt $NUM_CONFIGS || ${#PRIVATE_KEYS[@]} -lt $NUM_CONFIGS || ${#SHORT_IDS[@]} -lt $NUM_CONFIGS ]]; then
        log ERROR "Массивы ключей не соответствуют NUM_CONFIGS ($NUM_CONFIGS)"
        exit 1
    fi

    if ! build_domain_plan "$NUM_CONFIGS" "true"; then
        log ERROR "Не удалось сформировать доменный план для конфигурации"
        exit 1
    fi

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${DOMAIN_SELECTION_PLAN[$i]:-${AVAILABLE_DOMAINS[0]}}"

        build_inbound_profile_for_domain "$domain" fp_pool
        CONFIG_DOMAINS+=("$domain")
        CONFIG_SNIS+=("$PROFILE_SNI")
        CONFIG_TRANSPORT_ENDPOINTS+=("$PROFILE_TRANSPORT_ENDPOINT")
        CONFIG_DESTS+=("$PROFILE_DEST")
        CONFIG_FPS+=("$PROFILE_FP")
        CONFIG_PROVIDER_FAMILIES+=("$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")")

        local vless_pair vless_decryption vless_encryption
        vless_pair=$(generate_vless_encryption_pair) || exit 1
        IFS=$'\t' read -r vless_decryption vless_encryption <<< "$vless_pair"
        CONFIG_VLESS_DECRYPTIONS+=("$vless_decryption")
        CONFIG_VLESS_ENCRYPTIONS+=("$vless_encryption")

        local sni_count
        sni_count=$(echo "$PROFILE_SNI_JSON" | jq 'length' 2> /dev/null || echo 1)
        log INFO "Config $((i + 1)): ${domain} -> ${PROFILE_DEST} (${PROFILE_FP}, ${TRANSPORT}, SNIs: ${sni_count})"

        local inbound_v4
        inbound_v4=$(generate_profile_inbound_json \
            "${PORTS[$i]}" "${UUIDS[$i]}" "${PRIVATE_KEYS[$i]}" "${SHORT_IDS[$i]}" "${CONFIG_VLESS_DECRYPTIONS[$i]}")

        inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v4" '. + [$ib]')

        if [[ "$HAS_IPV6" == true ]]; then
            if [[ -z "${PORTS_V6[$i]:-}" ]]; then
                log ERROR "HAS_IPV6=true, но IPv6 порт для конфига #$((i + 1)) не задан"
                exit 1
            fi
            local inbound_v6
            if ! inbound_v6=$(echo "$inbound_v4" | jq --arg port "${PORTS_V6[$i]}" '.listen = "::" | .port = ($port|tonumber)' 2> /dev/null); then
                log ERROR "Ошибка генерации IPv6 inbound для конфига #$((i + 1)) (port=${PORTS_V6[$i]})"
                exit 1
            fi
            inbounds=$(echo "$inbounds" | jq --argjson ib "$inbound_v6" '. + [$ib]')
        fi

        progress_bar $((i + 1)) "$NUM_CONFIGS"
    done

    local outbounds
    outbounds=$(generate_outbounds_json)
    local routing
    routing=$(generate_routing_json)

    backup_file "$XRAY_CONFIG"
    local tmp_config
    tmp_config=$(create_temp_xray_config_file)
    jq -n \
        --argjson inbounds "$inbounds" \
        --argjson outbounds "$outbounds" \
        --argjson routing "$routing" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        '{
            log: {
                loglevel: "warning",
                access: "/var/log/xray/access.log",
                error: "/var/log/xray/error.log"
            },
            dns: {
                servers: [
                    "https+local://1.1.1.1/dns-query",
                    "https+local://8.8.8.8/dns-query",
                    "localhost"
                ],
                queryStrategy: "UseIPv4"
            },
            version: {
                min: $min_version
            },
            inbounds: $inbounds,
            outbounds: $outbounds,
            routing: $routing,
            policy: {
                levels: {
                    "0": {
                        handshake: 4,
                        connIdle: 600,
                        uplinkOnly: 2,
                        downlinkOnly: 5,
                        bufferSize: 1024
                    }
                },
                system: {
                    statsInboundUplink: false,
                    statsInboundDownlink: false
                }
            }
        }' > "$tmp_config"

    set_temp_xray_config_permissions "$tmp_config"

    if ! apply_validated_config "$tmp_config"; then
        exit 1
    fi

    log OK "Конфигурация создана"
}

rebuild_config_prepare_transport_context() {
    local target_transport="$1"
    local out_previous_transport_name="$2"

    if ((NUM_CONFIGS < 1)); then
        log ERROR "Нет конфигураций для rebuild transport"
        return 1
    fi

    check_xray_version_for_config_generation
    ensure_xray_feature_contract
    printf -v "$out_previous_transport_name" '%s' "${TRANSPORT:-xhttp}"
    TRANSPORT="$target_transport"
    setup_mux_settings
}

rebuild_config_collect_inbounds() {
    local target_transport="$1"
    local previous_transport="$2"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_inbounds="$3"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_domains="$4"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_snis="$5"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_endpoints="$6"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_dests="$7"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_fps="$8"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_provider_families="$9"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_vless_encryptions="${10}"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_vless_decryptions="${11}"
    local i

    for ((i = 0; i < NUM_CONFIGS; i++)); do
        local domain="${CONFIG_DOMAINS[$i]:-}"
        local sni="${CONFIG_SNIS[$i]:-$domain}"
        local fp="${CONFIG_FPS[$i]:-chrome}"
        local dest="${CONFIG_DESTS[$i]:-}"
        local transport_endpoint
        transport_endpoint="${CONFIG_TRANSPORT_ENDPOINTS[$i]:-}"
        local provider_family="${CONFIG_PROVIDER_FAMILIES[$i]:-}"
        local vless_encryption="${CONFIG_VLESS_ENCRYPTIONS[$i]:-}"
        local vless_decryption="${CONFIG_VLESS_DECRYPTIONS[$i]:-}"

        [[ -n "$domain" ]] || {
            log ERROR "Не найден домен для конфига #$((i + 1))"
            TRANSPORT="$previous_transport"
            return 1
        }
        [[ -n "$dest" ]] || dest="${domain}:$(detect_reality_dest "$domain")"
        [[ -n "$sni" ]] || sni="$domain"
        [[ -n "$provider_family" ]] || provider_family="$(domain_provider_family_for "$domain" 2> /dev/null || printf '%s' "$domain")"
        if [[ -z "$transport_endpoint" || "$target_transport" == "xhttp" ]]; then
            if [[ "$target_transport" == "xhttp" ]]; then
                transport_endpoint=$(generate_xhttp_path_for_domain "$domain")
            else
                transport_endpoint=$(select_legacy_transport_endpoint "$domain")
            fi
        fi

        local payload="$transport_endpoint"
        if [[ "$target_transport" == "http2" ]]; then
            payload=$(legacy_transport_endpoint_to_http2_path "$transport_endpoint")
        fi

        local sni_json
        sni_json=$(jq -cn --arg sni "$sni" '[$sni]')
        local keepalive grpc_idle grpc_health
        keepalive=$(rand_between "$TCP_KEEPALIVE_MIN" "$TCP_KEEPALIVE_MAX")
        grpc_idle=$(rand_between "$GRPC_IDLE_TIMEOUT_MIN" "$GRPC_IDLE_TIMEOUT_MAX")
        grpc_health=$(rand_between "$GRPC_HEALTH_TIMEOUT_MIN" "$GRPC_HEALTH_TIMEOUT_MAX")

        if [[ "$target_transport" == "xhttp" ]]; then
            if [[ -z "$vless_decryption" || "$vless_decryption" == "none" || -z "$vless_encryption" || "$vless_encryption" == "none" ]]; then
                local vless_pair
                vless_pair=$(generate_vless_encryption_pair) || {
                    TRANSPORT="$previous_transport"
                    return 1
                }
                IFS=$'\t' read -r vless_decryption vless_encryption <<< "$vless_pair"
            fi
        else
            vless_decryption="none"
            vless_encryption="none"
        fi

        local inbound_v4
        inbound_v4=$(generate_inbound_json \
            "${PORTS[$i]}" "${UUIDS[$i]}" "$dest" "$sni_json" "${PRIVATE_KEYS[$i]}" "${SHORT_IDS[$i]}" \
            "$fp" "$transport_endpoint" "$keepalive" "$grpc_idle" "$grpc_health" \
            "$target_transport" "$payload" "$vless_decryption" "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}")
        out_inbounds=$(echo "$out_inbounds" | jq --argjson ib "$inbound_v4" '. + [$ib]')

        if [[ "$HAS_IPV6" == true && -n "${PORTS_V6[$i]:-}" ]]; then
            local inbound_v6
            inbound_v6=$(echo "$inbound_v4" | jq --arg port "${PORTS_V6[$i]}" '.listen = "::" | .port = ($port|tonumber)')
            out_inbounds=$(echo "$out_inbounds" | jq --argjson ib "$inbound_v6" '. + [$ib]')
        fi

        out_domains+=("$domain")
        out_snis+=("$sni")
        out_endpoints+=("$transport_endpoint")
        out_dests+=("$dest")
        out_fps+=("$fp")
        out_provider_families+=("$provider_family")
        out_vless_encryptions+=("$vless_encryption")
        out_vless_decryptions+=("$vless_decryption")
    done
}

rebuild_config_write_candidate() {
    local target_transport="$1"
    local previous_transport="$2"
    local inbounds="$3"
    local outbounds routing tmp_config

    outbounds=$(generate_outbounds_json)
    routing=$(generate_routing_json)
    backup_file "$XRAY_CONFIG"
    tmp_config=$(create_temp_xray_config_file)
    jq -n \
        --argjson inbounds "$inbounds" \
        --argjson outbounds "$outbounds" \
        --argjson routing "$routing" \
        --arg min_version "${XRAY_CLIENT_MIN_VERSION:-25.9.5}" \
        '{
            log: {
                loglevel: "warning",
                access: "/var/log/xray/access.log",
                error: "/var/log/xray/error.log"
            },
            dns: {
                servers: [
                    "https+local://1.1.1.1/dns-query",
                    "https+local://8.8.8.8/dns-query",
                    "localhost"
                ],
                queryStrategy: "UseIPv4"
            },
            version: {
                min: $min_version
            },
            inbounds: $inbounds,
            outbounds: $outbounds,
            routing: $routing,
            policy: {
                levels: {
                    "0": {
                        handshake: 4,
                        connIdle: 600,
                        uplinkOnly: 2,
                        downlinkOnly: 5,
                        bufferSize: 1024
                    }
                },
                system: {
                    statsInboundUplink: false,
                    statsInboundDownlink: false
                }
            }
        }' > "$tmp_config"
    set_temp_xray_config_permissions "$tmp_config"
    if ! apply_validated_config "$tmp_config"; then
        TRANSPORT="$previous_transport"
        return 1
    fi
    TRANSPORT="$target_transport"
}

rebuild_config_commit_runtime_state() {
    local target_transport="$1"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_domains_ref="$2"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_snis_ref="$3"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_endpoints_ref="$4"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_dests_ref="$5"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_fps_ref="$6"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_provider_families_ref="$7"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_vless_encryptions_ref="$8"
    # shellcheck disable=SC2034 # Used as nameref input parameter.
    local -n next_vless_decryptions_ref="$9"

    CONFIG_DOMAINS=("${next_domains_ref[@]}")
    CONFIG_SNIS=("${next_snis_ref[@]}")
    CONFIG_TRANSPORT_ENDPOINTS=("${next_endpoints_ref[@]}")
    CONFIG_DESTS=("${next_dests_ref[@]}")
    CONFIG_FPS=("${next_fps_ref[@]}")
    CONFIG_PROVIDER_FAMILIES=("${next_provider_families_ref[@]}")
    CONFIG_VLESS_ENCRYPTIONS=("${next_vless_encryptions_ref[@]}")
    CONFIG_VLESS_DECRYPTIONS=("${next_vless_decryptions_ref[@]}")
    TRANSPORT="$target_transport"
}

rebuild_config_for_transport() {
    local target_transport="${1:-xhttp}"
    local inbounds='[]'
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_domains=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_snis=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_endpoints=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_dests=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_fps=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_provider_families=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_vless_encryptions=()
    # shellcheck disable=SC2034 # Used via nameref helpers.
    local -a next_vless_decryptions=()
    local previous_transport="${TRANSPORT:-xhttp}"
    rebuild_config_prepare_transport_context "$target_transport" previous_transport || return 1
    rebuild_config_collect_inbounds \
        "$target_transport" "$previous_transport" \
        inbounds next_domains next_snis next_endpoints next_dests next_fps next_provider_families \
        next_vless_encryptions next_vless_decryptions || return 1
    rebuild_config_write_candidate "$target_transport" "$previous_transport" "$inbounds" || return 1
    rebuild_config_commit_runtime_state \
        "$target_transport" \
        next_domains next_snis next_endpoints next_dests next_fps next_provider_families \
        next_vless_encryptions next_vless_decryptions
    return 0
}
