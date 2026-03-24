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
    local -a legacy_endpoint_fallbacks=(
        "cdn.storage.v1.UploadService"
        "api.internal.health.v1.HealthCheck"
        "cloud.metrics.v1.CollectorService"
    )
    local -a legacy_endpoint_candidates=()
    local legacy_endpoint_pool="${TRANSPORT_ENDPOINT_SEEDS[$domain]:-}"

    if [[ -n "$legacy_endpoint_pool" ]]; then
        local -a legacy_endpoint_array=()
        local svc
        read -r -a legacy_endpoint_array <<< "$legacy_endpoint_pool"
        for svc in "${legacy_endpoint_array[@]}"; do
            if is_valid_grpc_service_name "$svc"; then
                legacy_endpoint_candidates+=("$svc")
            else
                log WARN "Пропускаем невалидный legacy transport endpoint seed для ${domain}: ${svc}"
            fi
        done
    fi
    if ((${#legacy_endpoint_candidates[@]} == 0)); then
        legacy_endpoint_candidates=("${legacy_endpoint_fallbacks[@]}")
    fi

    pick_random_from_array legacy_endpoint_candidates
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

build_inbound_profile_for_domain_values() {
    local domain="$1"
    local fp_pool_name="$2"
    local out_sni_name="$3"
    local out_sni_json_name="$4"
    local out_transport_endpoint_name="$5"
    local out_fp_name="$6"
    local out_dest_name="$7"
    local out_keepalive_name="$8"
    local out_grpc_idle_name="$9"
    local out_grpc_health_name="${10}"
    local out_transport_payload_name="${11}"
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

    local selected_sni=""
    if ! selected_sni=$(pick_random_from_array sni_array); then
        selected_sni="$domain"
        sni_array=("$domain")
    fi
    if [[ "$DOMAIN_CHECK" == "true" && "$selected_sni" != "$domain" ]]; then
        if ! check_domain_alive "$selected_sni"; then
            log WARN "SNI ${selected_sni} недоступен; fallback на ${domain}"
            selected_sni="$domain"
        fi
    fi

    local -a server_names=("$selected_sni")
    local _sn
    for _sn in "${sni_array[@]}"; do
        [[ "$_sn" == "$selected_sni" ]] && continue
        server_names+=("$_sn")
        [[ ${#server_names[@]} -ge 3 ]] && break
    done
    local selected_sni_json=""
    selected_sni_json=$(printf '%s\n' "${server_names[@]}" | jq -R . | jq -s .)

    local selected_transport_endpoint=""
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        selected_transport_endpoint=$(generate_xhttp_path_for_domain "$domain")
    else
        selected_transport_endpoint=$(select_legacy_transport_endpoint "$domain")
    fi
    local selected_fp=""
    if ! selected_fp=$(pick_random_from_array _fp_pool); then
        selected_fp="chrome"
    fi

    local dest_port
    dest_port=$(detect_reality_dest "$domain")
    local selected_dest="${domain}:${dest_port}"

    local selected_keepalive
    local selected_grpc_idle
    local selected_grpc_health
    selected_keepalive=$(rand_between "$TCP_KEEPALIVE_MIN" "$TCP_KEEPALIVE_MAX")
    selected_grpc_idle=$(rand_between "$GRPC_IDLE_TIMEOUT_MIN" "$GRPC_IDLE_TIMEOUT_MAX")
    selected_grpc_health=$(rand_between "$GRPC_HEALTH_TIMEOUT_MIN" "$GRPC_HEALTH_TIMEOUT_MAX")

    local selected_transport_payload="$selected_transport_endpoint"
    if [[ "$TRANSPORT" == "http2" ]]; then
        selected_transport_payload=$(legacy_transport_endpoint_to_http2_path "$selected_transport_endpoint")
    fi

    printf -v "$out_sni_name" '%s' "$selected_sni"
    printf -v "$out_sni_json_name" '%s' "$selected_sni_json"
    printf -v "$out_transport_endpoint_name" '%s' "$selected_transport_endpoint"
    printf -v "$out_fp_name" '%s' "$selected_fp"
    printf -v "$out_dest_name" '%s' "$selected_dest"
    printf -v "$out_keepalive_name" '%s' "$selected_keepalive"
    printf -v "$out_grpc_idle_name" '%s' "$selected_grpc_idle"
    printf -v "$out_grpc_health_name" '%s' "$selected_grpc_health"
    printf -v "$out_transport_payload_name" '%s' "$selected_transport_payload"
}

generate_profile_inbound_json() {
    local port="$1"
    local uuid="$2"
    local private_key="$3"
    local short_id="$4"
    local decryption_value="${5:-none}"
    local profile_dest="$6"
    local profile_sni_json="$7"
    local profile_fp="$8"
    local profile_transport_endpoint="$9"
    local profile_keepalive="${10}"
    local profile_grpc_idle="${11}"
    local profile_grpc_health="${12}"
    local profile_transport_value="${13:-$TRANSPORT}"
    local profile_transport_payload="${14:-$profile_transport_endpoint}"

    generate_inbound_json \
        "$port" "$uuid" "$profile_dest" "$profile_sni_json" "$private_key" "$short_id" \
        "$profile_fp" "$profile_transport_endpoint" "$profile_keepalive" "$profile_grpc_idle" "$profile_grpc_health" \
        "$profile_transport_value" "$profile_transport_payload" "$decryption_value" "${XRAY_DIRECT_FLOW:-xtls-rprx-vision}"
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
