#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154 # sourced config modules intentionally consume runtime globals from lib.sh/globals_contract.sh

: "${UI_BOX_H:=─}"
: "${XRAY_KEYS:=/etc/xray/private/keys}"
: "${SCRIPT_VERSION:=unknown}"
: "${XRAY_GROUP:=xray}"
: "${DOMAIN_TIER:=tier_ru}"
: "${HAS_IPV6:=false}"
: "${QR_ENABLED:=false}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
if ! declare -p UUIDS > /dev/null 2>&1; then UUIDS=(); fi
if ! declare -p PUBLIC_KEYS > /dev/null 2>&1; then PUBLIC_KEYS=(); fi
if ! declare -p SHORT_IDS > /dev/null 2>&1; then SHORT_IDS=(); fi
if ! declare -p PORTS > /dev/null 2>&1; then PORTS=(); fi
if ! declare -p PORTS_V6 > /dev/null 2>&1; then PORTS_V6=(); fi

update_env_num_configs() {
    local env_file="$1"
    local total="$2"
    [[ -f "$env_file" ]] || return 0
    [[ "$total" =~ ^[0-9]+$ ]] || return 1

    backup_file "$env_file"
    local tmp_env
    tmp_env=$(mktemp "${env_file}.tmp.XXXXXX")

    awk -v total="$total" '
        BEGIN { has_num=0; has_xnum=0 }
        /^NUM_CONFIGS=/ {
            print "NUM_CONFIGS=\"" total "\""
            has_num=1
            next
        }
        /^XRAY_NUM_CONFIGS=/ {
            print "XRAY_NUM_CONFIGS=\"" total "\""
            has_xnum=1
            next
        }
        { print }
        END {
            if (!has_num) {
                print "NUM_CONFIGS=\"" total "\""
            }
            if (!has_xnum) {
                print "XRAY_NUM_CONFIGS=\"" total "\""
            }
        }
    ' "$env_file" > "$tmp_env"

    mv "$tmp_env" "$env_file"
    chmod 600 "$env_file"
}

validate_clients_json_file() {
    local json_file="$1"
    local clients_shape_filter=""
    [[ -f "$json_file" ]] || return 0

    clients_shape_filter=$(
        cat << 'JQ'
type == "object"
and (.configs | type == "array")
and ((.schema_version // 0) >= 2)
and ((.configs | length) < 1 or ([.configs[]? | (((.variants | arrays | length) // 0) >= 1)] | all))
JQ
    )

    if jq -e "$clients_shape_filter" "$json_file" > /dev/null 2>&1; then
        return 0
    fi

    local normalized_json=""
    if jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(cat "$json_file")
    elif jq -e 'type == "array"' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq -n --slurpfile cfg "$json_file" '{configs: $cfg[0]}')
    elif jq -e 'type == "object" and (.profiles | type == "array")' "$json_file" > /dev/null 2>&1; then
        normalized_json=$(jq '. + {configs: .profiles} | del(.profiles)' "$json_file")
    else
        normalized_json='{"configs":[]}'
        log WARN "Некорректный формат ${json_file}; файл будет пересоздан в схеме .configs"
    fi

    normalized_json=$(printf '%s\n' "$normalized_json" | jq '
        .schema_version = 3
        | .stealth_contract_version = (.stealth_contract_version // "7.3.8")
        | .transport = (.transport // "xhttp")
        | .xray_min_version = (.xray_min_version // "25.9.5")
        | .configs = (
            (.configs // [])
            | map(
                . as $cfg
                | ($cfg.variants // []) as $variants
                | .provider_family = ($cfg.provider_family // ($cfg.domain // ""))
                | .primary_rank = ($cfg.primary_rank // 0)
                | .transport = ($cfg.transport // $cfg.transport_type // ($variants[0].transport // "xhttp"))
                | .transport_endpoint = ($cfg.transport_endpoint // $cfg.grpc_service // ($variants[0].transport_endpoint // ""))
                | .flow = ($cfg.flow // "xtls-rprx-vision")
                | .vless_encryption = ($cfg.vless_encryption // "none")
                | .vless_decryption = ($cfg.vless_decryption // "none")
                | .recommended_variant = ($cfg.recommended_variant // ($variants[0].key // "recommended"))
                | .variants = (
                    if ($variants | type == "array" and ($variants | length) > 0) then
                        ($variants | map(
                            .key = (.key // "recommended")
                            | .category = (.category // (
                                if .key == "recommended" then "direct"
                                elif .key == "rescue" then "fallback"
                                elif .key == "emergency" then "emergency"
                                else "legacy"
                                end
                              ))
                            | .label = (.label // .key // "recommended")
                            | .note = (.note // "normalized from legacy schema")
                            | .transport = (.transport // $cfg.transport // "xhttp")
                            | .transport_endpoint = (.transport_endpoint // $cfg.transport_endpoint // "")
                            | .requires = (.requires // {
                                browser_dialer: (.key == "emergency"),
                                vless_encryption: (($cfg.vless_encryption // "none") != "none"),
                                flow: ($cfg.flow // "xtls-rprx-vision")
                              })
                            | .import_hint = (.import_hint // (
                                if .key == "emergency" then "raw xray json only; requires browser dialer on the client"
                                elif .key == "rescue" then "use raw xray json if the normal variant is unstable"
                                else "import raw xray json when possible; vless link is secondary"
                                end
                              ))
                        ))
                    else
                        [{
                            key: (.recommended_variant // "recommended"),
                            category: "direct",
                            label: (.recommended_variant // "recommended"),
                            note: "normalized from legacy schema",
                            mode: (if (.transport // "xhttp") == "xhttp" then "auto" else null end),
                            transport: (.transport // "xhttp"),
                            transport_endpoint: (.transport_endpoint // .grpc_service // ""),
                            requires: {
                                browser_dialer: false,
                                vless_encryption: (($cfg.vless_encryption // "none") != "none"),
                                flow: ($cfg.flow // "xtls-rprx-vision")
                            },
                            import_hint: "import raw xray json when possible; vless link is secondary",
                            vless_v4: (.vless_v4 // null),
                            vless_v6: (.vless_v6 // null),
                            xray_client_file_v4: null,
                            xray_client_file_v6: null
                        }]
                    end
                )
            )
        )')

    if ! printf '%s\n' "$normalized_json" | jq -e 'type == "object" and (.configs | type == "array") and (.schema_version // 0) >= 3' > /dev/null 2>&1; then
        log ERROR "Не удалось привести ${json_file} к схеме .configs"
        return 1
    fi

    printf '%s\n' "$normalized_json" | atomic_write "$json_file" 0640
    secure_clients_json_permissions "$json_file"
    log WARN "Нормализован legacy-формат ${json_file} -> schema v3"
    return 0
}

collect_fallback_public_keys_from_artifacts() {
    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
    local client_links_file="${XRAY_KEYS}/clients-links.txt"
    local json_file="${XRAY_KEYS}/clients.json"
    local required_count="${1:-0}"

    local -a from_keys=()
    local -a from_json=()
    local -a from_clients=()

    if [[ -f "$keys_file" ]]; then
        mapfile -t from_keys < <(awk -F'Public Key:[[:space:]]*' '
            /^Public Key:/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                if ($2 != "") print $2
            }
        ' "$keys_file")
    fi

    if [[ -f "$json_file" ]] && command -v jq > /dev/null 2>&1; then
        mapfile -t from_json < <(jq -r '.configs[]?.public_key // empty' "$json_file" 2> /dev/null)
    fi

    if [[ -f "$client_file" ]]; then
        local line params pbk seen=" "
        while IFS= read -r line; do
            [[ "$line" == vless://* ]] || continue
            [[ "$line" == *"@["* ]] && continue
            params="${line#*\?}"
            params="${params%%#*}"
            pbk=$(get_query_param "$params" "pbk" || true)
            [[ -n "$pbk" ]] || continue
            [[ " $seen " == *" $pbk "* ]] && continue
            seen="${seen}${pbk} "
            from_clients+=("$pbk")
        done < "$client_file"
    fi

    if [[ -f "$client_links_file" ]]; then
        local line params pbk seen_links=" "
        while IFS= read -r line; do
            [[ "$line" == vless://* ]] || continue
            [[ "$line" == *"@["* ]] && continue
            params="${line#*\?}"
            params="${params%%#*}"
            pbk=$(get_query_param "$params" "pbk" || true)
            [[ -n "$pbk" ]] || continue
            [[ " $seen_links " == *" $pbk "* ]] && continue
            seen_links="${seen_links}${pbk} "
            from_clients+=("$pbk")
        done < "$client_links_file"
    fi

    local -a best=("${from_keys[@]}")
    if ((${#from_json[@]} > ${#best[@]})); then
        best=("${from_json[@]}")
    fi
    if ((${#from_clients[@]} > ${#best[@]})); then
        best=("${from_clients[@]}")
    fi

    if ((required_count > 0 && ${#best[@]} > required_count)); then
        best=("${best[@]:0:required_count}")
    fi
    printf '%s\n' "${best[@]}"
}

derive_public_key_from_private_key() {
    local private_key="$1"
    [[ -n "$private_key" ]] || return 1
    [[ -x "$XRAY_BIN" ]] || return 1

    local key_output pub
    if ! key_output=$("$XRAY_BIN" x25519 -i "$private_key" 2>&1); then
        debug_file "xray x25519 -i failed while deriving public key: ${key_output}"
        return 1
    fi
    pub=$(printf '%s\n' "$key_output" | sed -n 's/.*Public key:[[:space:]]*//p' | head -n 1 | tr -d '\r')

    if [[ "$pub" =~ ^[A-Za-z0-9_-]{20,128}$ ]]; then
        printf '%s\n' "$pub"
        return 0
    fi
    return 1
}

build_public_keys_for_current_config() {
    local required_count=${#PORTS[@]}
    if ((required_count < 1)); then
        log ERROR "Нет портов в текущей конфигурации для восстановления public keys"
        return 1
    fi

    local -a fallback_public_keys=()
    mapfile -t fallback_public_keys < <(collect_fallback_public_keys_from_artifacts "$required_count")

    PUBLIC_KEYS=()
    local i pub
    for ((i = 0; i < required_count; i++)); do
        pub=""
        if [[ -n "${PRIVATE_KEYS[$i]:-}" ]]; then
            pub=$(derive_public_key_from_private_key "${PRIVATE_KEYS[$i]}" || true)
        fi
        if [[ -z "$pub" && -n "${fallback_public_keys[$i]:-}" ]]; then
            pub="${fallback_public_keys[$i]}"
        fi
        if [[ -z "$pub" ]]; then
            log ERROR "Не удалось восстановить public key для конфига #$((i + 1))"
            return 1
        fi
        PUBLIC_KEYS+=("$pub")
    done
    return 0
}

client_artifacts_missing() {
    local -a files=(
        "${XRAY_KEYS}/keys.txt"
        "${XRAY_KEYS}/clients.txt"
        "${XRAY_KEYS}/clients-links.txt"
        "${XRAY_KEYS}/clients.json"
    )
    local missing=false
    local file
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log WARN "Отсутствует клиентский артефакт: ${file}"
            missing=true
        fi
    done
    [[ "$missing" == true ]]
}

client_artifacts_inconsistent() {
    local expected_count="${1:-0}"
    if [[ ! "$expected_count" =~ ^[0-9]+$ ]] || ((expected_count < 1)); then
        expected_count="${#PORTS[@]}"
    fi
    if ((expected_count < 1)); then
        return 1
    fi

    local keys_file="${XRAY_KEYS}/keys.txt"
    local client_file="${XRAY_KEYS}/clients.txt"
    local client_links_file="${XRAY_KEYS}/clients-links.txt"
    local json_file="${XRAY_KEYS}/clients.json"

    local inconsistent=false
    local count

    if [[ -f "$keys_file" ]]; then
        count=$(awk '/^Private Key:/ {c++} END {print c+0}' "$keys_file")
        if ((count != expected_count)); then
            log WARN "keys.txt рассинхронизирован: ${count}/${expected_count}"
            inconsistent=true
        fi
    fi

    local section_pattern='([Cc]onfig|конфиг) [0-9]+:'

    if [[ -f "$client_file" ]]; then
        count=$(awk -v pattern="$section_pattern" '$0 ~ pattern {c++} END {print c+0}' "$client_file")
        if ((count != expected_count)); then
            log WARN "clients.txt рассинхронизирован: ${count}/${expected_count} секций"
            inconsistent=true
        fi
    fi

    if [[ -f "$client_links_file" ]]; then
        count=$(awk -v pattern="$section_pattern" '$0 ~ pattern {c++} END {print c+0}' "$client_links_file")
        if ((count != expected_count)); then
            log WARN "clients-links.txt рассинхронизирован: ${count}/${expected_count} секций"
            inconsistent=true
        fi
    fi

    if [[ -f "$json_file" ]]; then
        if ! jq -e 'type == "object" and (.configs | type == "array")' "$json_file" > /dev/null 2>&1; then
            log WARN "clients.json имеет некорректную схему"
            inconsistent=true
        else
            count=$(jq -r '.configs | length' "$json_file" 2> /dev/null || echo 0)
            if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count != expected_count)); then
                log WARN "clients.json рассинхронизирован: ${count}/${expected_count}"
                inconsistent=true
            fi
        fi
    fi

    [[ "$inconsistent" == true ]]
}

client_artifacts_ready_for_self_check() {
    local json_file="${XRAY_KEYS}/clients.json"
    local capabilities_file="${XRAY_KEYS}/export/capabilities.json"

    if client_artifacts_missing; then
        return 1
    fi
    if client_artifacts_inconsistent "${#PORTS[@]}"; then
        return 1
    fi
    if [[ ! -f "$capabilities_file" ]]; then
        log WARN "Отсутствует capability matrix: ${capabilities_file}"
        return 1
    fi
    if ! jq -e '.formats | type == "array"' "$capabilities_file" > /dev/null 2>&1; then
        log WARN "capabilities.json имеет некорректную схему"
        return 1
    fi
    if ! jq -e '
        type == "object"
        and (.configs | type == "array")
        and ([.configs[] | .variants[] | (.xray_client_file_v4 // empty)] | map(select(length > 0)) | length) >= 1
    ' "$json_file" > /dev/null 2>&1; then
        log WARN "clients.json не содержит пригодных raw xray variants для self-check"
        return 1
    fi
    local declared_raw
    while IFS= read -r declared_raw; do
        [[ -n "$declared_raw" ]] || continue
        if [[ ! -f "$declared_raw" ]]; then
            log WARN "Отсутствует raw xray variant: ${declared_raw}"
            return 1
        fi
    done < <(jq -r '.configs[] | .variants[] | .xray_client_file_v4 // empty, .xray_client_file_v6 // empty' "$json_file" 2> /dev/null)
    return 0
}

ensure_self_check_artifacts_ready() {
    if client_artifacts_ready_for_self_check; then
        return 0
    fi
    log INFO "Артефакты self-check отсутствуют или устарели; пересобираем"
    rebuild_client_artifacts_from_config || return 1
    client_artifacts_ready_for_self_check
}

rebuild_client_artifacts_from_loaded_state() {
    save_client_configs || return 1
    if declare -F export_all_configs > /dev/null 2>&1; then
        export_all_configs || return 1
    fi
    return 0
}

rebuild_client_artifacts_from_config() {
    log STEP "Пересобираем клиентские артефакты из текущей конфигурации..."

    load_existing_ports_from_config
    load_existing_metadata_from_config
    load_keys_from_config

    NUM_CONFIGS=${#PORTS[@]}
    if ((NUM_CONFIGS < 1)); then
        log ERROR "Не найдены inbounds для пересборки клиентских артефактов"
        return 1
    fi

    if ! build_public_keys_for_current_config; then
        return 1
    fi

    rebuild_client_artifacts_from_loaded_state || return 1
    log OK "Клиентские артефакты пересобраны из config.json"
    return 0
}
