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

self_check_log() {
    local level="${1:-INFO}"
    shift || true
    if declare -F log > /dev/null 2>&1; then
        log "$level" "$*"
    else
        printf '[%s] %s\n' "$level" "$*" >&2
    fi
}

self_check_debug() {
    if declare -F debug_file > /dev/null 2>&1; then
        debug_file "$*"
    fi
}

self_check_backup_file() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 0
    if declare -F backup_file > /dev/null 2>&1; then
        backup_file "$path"
    fi
}

self_check_atomic_write() {
    local target="$1"
    local mode="$2"
    if declare -F atomic_write > /dev/null 2>&1; then
        atomic_write "$target" "$mode"
        return 0
    fi

    local tmp
    tmp=$(mktemp "${target}.tmp.XXXXXX") || return 1
    cat > "$tmp"
    chmod "$mode" "$tmp"
    mv "$tmp" "$target"
}

self_check_trim_ws() {
    local value="${1:-}"
    if declare -F trim_ws > /dev/null 2>&1; then
        trim_ws "$value"
        return 0
    fi
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

self_check_split_list() {
    local raw="${1:-}"
    if declare -F split_list > /dev/null 2>&1; then
        split_list "$raw"
        return 0
    fi
    printf '%s\n' "$raw" | tr ', ' '\n\n' | sed '/^$/d'
}

self_check_port_is_listening() {
    local port="${1:-}"
    if declare -F port_is_listening > /dev/null 2>&1; then
        port_is_listening "$port"
        return $?
    fi
    ss -ltn "( sport = :${port} )" 2> /dev/null | tail -n +2 | grep -q .
}

self_check_state_file_path() {
    printf '%s\n' "${SELF_CHECK_STATE_FILE:-/var/lib/xray/self-check.json}"
}

self_check_default_urls() {
    printf '%s\n' "${SELF_CHECK_URLS:-https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204}"
}

self_check_urls_json() {
    local raw_urls
    raw_urls=$(self_check_default_urls)
    jq -Rn --arg raw "$raw_urls" '
        ($raw | gsub("[[:space:]]+"; " ") | split(","))
        | map(split(" "))
        | add
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | unique
    '
}

self_check_now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

self_check_pick_free_port() {
    local base=38080
    local span=800
    local attempt candidate
    for attempt in $(seq 1 64); do
        candidate=$((base + RANDOM % span))
        if ! self_check_port_is_listening "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    for candidate in $(seq $base $((base + span))); do
        if ! self_check_port_is_listening "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

self_check_prepare_runtime_config() {
    local source_file="$1"
    local socks_port="$2"
    local target_file="$3"

    jq --argjson socks_port "$socks_port" '
        .log = { loglevel: "warning" }
        | .inbounds = (
            (.inbounds // [])
            | map(
                if (.protocol // "") == "socks" then
                    .listen = "127.0.0.1"
                    | .port = $socks_port
                else
                    .
                end
            )
        )
    ' "$source_file" > "$target_file"
}

self_check_start_client_process() {
    local config_file="$1"
    local log_file="$2"
    "$XRAY_BIN" run -config "$config_file" > "$log_file" 2>&1 &
    local pid=$!
    printf '%s\n' "$pid"
}

self_check_stop_client_process() {
    local pid="${1:-}"
    [[ -n "$pid" ]] || return 0
    if kill -0 "$pid" 2> /dev/null; then
        kill "$pid" 2> /dev/null || true
        wait "$pid" 2> /dev/null || true
    fi
}

self_check_wait_for_proxy() {
    local port="$1"
    local attempts=0
    local max_attempts=40

    while ((attempts < max_attempts)); do
        if self_check_port_is_listening "$port"; then
            return 0
        fi
        sleep 0.25
        attempts=$((attempts + 1))
    done
    return 1
}

self_check_probe_single_url() {
    local proxy_port="$1"
    local url="$2"
    local timeout_sec="$3"
    local curl_output=""
    local curl_status=0
    local http_code="000"
    local time_total="0"
    local latency_ms=0
    local error_text=""
    local success=false

    curl_output=$(curl \
        --silent --show-error \
        --location \
        --output /dev/null \
        --proxy "socks5h://127.0.0.1:${proxy_port}" \
        --connect-timeout "$timeout_sec" \
        --max-time "$timeout_sec" \
        --write-out '%{http_code} %{time_total}' \
        "$url" 2>&1) || curl_status=$?

    if ((curl_status == 0)); then
        http_code=$(awk '{print $1}' <<< "$curl_output")
        time_total=$(awk '{print $2}' <<< "$curl_output")
        latency_ms=$(awk -v t="${time_total:-0}" 'BEGIN { printf "%d", (t + 0) * 1000 + 0.5 }')
        if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            success=true
        else
            error_text="unexpected_http_${http_code}"
        fi
    else
        error_text=$(printf '%s' "$curl_output" | tail -n 1 | tr '\r' ' ' | sed 's/[[:space:]]\+/ /g')
        error_text=$(self_check_trim_ws "$error_text")
        [[ -n "$error_text" ]] || error_text="curl_exit_${curl_status}"
    fi

    jq -n \
        --arg url "$url" \
        --arg http_code "$http_code" \
        --argjson latency_ms "${latency_ms:-0}" \
        --arg error_text "$error_text" \
        --argjson success "$success" \
        '{
            url: $url,
            http_code: $http_code,
            latency_ms: $latency_ms,
            success: $success,
            error: (if ($error_text | length) > 0 then $error_text else null end)
        }'
}

self_check_run_variant_probe() {
    local action="$1"
    local config_name="$2"
    local variant_key="$3"
    local mode="$4"
    local ip_family="$5"
    local raw_config_file="$6"
    local tmp_dir=""
    local runtime_config=""
    local runtime_log=""
    local proxy_port=""
    local pid=""
    local reason=""
    local probe_results='[]'
    local urls_json='[]'
    local selected_url=""
    local best_latency_ms=0
    local success=false

    if [[ "${SELF_CHECK_ENABLED:-true}" != "true" ]]; then
        jq -n \
            --arg action "$action" \
            --arg config_name "$config_name" \
            --arg variant_key "$variant_key" \
            --arg mode "$mode" \
            --arg ip_family "$ip_family" \
            '{
                checked_at: now | todateiso8601,
                action: $action,
                config_name: $config_name,
                variant_key: $variant_key,
                mode: (if ($mode | length) > 0 then $mode else null end),
                ip_family: $ip_family,
                success: false,
                skipped: true,
                reason: "self_check_disabled",
                probe_results: []
            }'
        return 0
    fi

    if [[ ! -x "$XRAY_BIN" ]]; then
        reason="xray_bin_missing"
    elif [[ ! -f "$raw_config_file" ]]; then
        reason="raw_config_missing"
    fi

    if [[ -z "$reason" ]]; then
        if ! proxy_port=$(self_check_pick_free_port); then
            reason="no_free_local_proxy_port"
        fi
    fi

    if [[ -z "$reason" ]]; then
        tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/xray-self-check.XXXXXX") || reason="tmpdir_create_failed"
    fi

    if [[ -z "$reason" ]]; then
        runtime_config="${tmp_dir}/client.json"
        runtime_log="${tmp_dir}/client.log"
        if ! self_check_prepare_runtime_config "$raw_config_file" "$proxy_port" "$runtime_config"; then
            reason="runtime_config_prepare_failed"
        fi
    fi

    if [[ -z "$reason" ]] && declare -F xray_config_test_ok > /dev/null 2>&1; then
        if ! xray_config_test_ok "$runtime_config" > /dev/null 2>&1; then
            reason="runtime_config_test_failed"
        fi
    fi

    if [[ -z "$reason" ]]; then
        pid=$(self_check_start_client_process "$runtime_config" "$runtime_log")
        if [[ -z "$pid" ]]; then
            reason="client_start_failed"
        elif ! self_check_wait_for_proxy "$proxy_port"; then
            reason="proxy_not_ready"
            self_check_debug "self-check proxy failed to start for ${config_name}/${variant_key}; log=$(tail -n 20 \"$runtime_log\" 2>/dev/null || true)"
        fi
    fi

    if [[ -z "$reason" ]]; then
        urls_json=$(self_check_urls_json)
        while IFS= read -r url; do
            [[ -n "$url" ]] || continue
            local single_result=""
            single_result=$(self_check_probe_single_url "$proxy_port" "$url" "${SELF_CHECK_TIMEOUT_SEC:-8}")
            probe_results=$(jq --argjson item "$single_result" '. + [$item]' <<< "$probe_results")
        done < <(jq -r '.[]' <<< "$urls_json")

        if jq -e 'any(.[]; .success == true)' <<< "$probe_results" > /dev/null 2>&1; then
            success=true
            selected_url=$(jq -r '[.[] | select(.success == true)] | sort_by(.latency_ms) | .[0].url // ""' <<< "$probe_results")
            best_latency_ms=$(jq -r '[.[] | select(.success == true)] | sort_by(.latency_ms) | .[0].latency_ms // 0' <<< "$probe_results")
        else
            reason=$(jq -r '[.[] | .error // ("http_" + .http_code)] | map(select(length > 0)) | first // "probe_failed"' <<< "$probe_results")
        fi
    fi

    self_check_stop_client_process "$pid"
    [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"

    jq -n \
        --arg checked_at "$(self_check_now_utc)" \
        --arg action "$action" \
        --arg config_name "$config_name" \
        --arg variant_key "$variant_key" \
        --arg mode "$mode" \
        --arg ip_family "$ip_family" \
        --arg raw_config_file "$raw_config_file" \
        --arg selected_url "$selected_url" \
        --arg reason "$reason" \
        --argjson success "$success" \
        --argjson latency_ms "${best_latency_ms:-0}" \
        --argjson probe_results "$probe_results" \
        '{
            checked_at: $checked_at,
            action: $action,
            config_name: $config_name,
            variant_key: $variant_key,
            mode: (if ($mode | length) > 0 then $mode else null end),
            ip_family: $ip_family,
            raw_config_file: $raw_config_file,
            success: $success,
            latency_ms: $latency_ms,
            selected_url: (if ($selected_url | length) > 0 then $selected_url else null end),
            reason: (if ($reason | length) > 0 then $reason else null end),
            probe_results: $probe_results
        }'
}

self_check_config_job_json() {
    local json_file="$1"
    local config_index="$2"
    local variant_key="$3"
    variant_key=${variant_key//$'\r'/}
    variant_key=$(self_check_trim_ws "$variant_key")
    jq -c --argjson config_index "$config_index" --arg variant_key "$variant_key" '
        .configs[$config_index] as $cfg
        | select($cfg != null)
        | ($cfg.variants[] | select(.key == $variant_key) | {
            config_index: $config_index,
            config_name: $cfg.name,
            variant_key: .key,
            mode: (.mode // ""),
            raw_v4: (.xray_client_file_v4 // ""),
            raw_v6: (.xray_client_file_v6 // "")
        })
    ' "$json_file" 2> /dev/null | head -n 1
}

self_check_first_raw_file_for_job() {
    local job_json="$1"
    local raw_v4 raw_v6
    raw_v4=$(jq -r '.raw_v4 // empty' <<< "$job_json")
    raw_v6=$(jq -r '.raw_v6 // empty' <<< "$job_json")
    raw_v4=${raw_v4//$'\r'/}
    raw_v6=${raw_v6//$'\r'/}
    raw_v4=$(self_check_trim_ws "$raw_v4")
    raw_v6=$(self_check_trim_ws "$raw_v6")
    if [[ -n "$raw_v4" ]]; then
        printf 'ipv4\t%s\n' "$raw_v4"
        return 0
    fi
    if [[ -n "$raw_v6" ]]; then
        printf 'ipv6\t%s\n' "$raw_v6"
        return 0
    fi
    return 1
}

self_check_preferred_variant_keys() {
    local json_file="$1"
    local config_index="$2"
    jq -r --argjson config_index "$config_index" '
        (.configs[$config_index] // {}) as $cfg
        | [($cfg.recommended_variant // "recommended"), "rescue"]
        | map(select(type == "string" and length > 0))
        | unique[]
    ' "$json_file" 2> /dev/null
}

self_check_write_state_json() {
    local state_json="$1"
    local state_file
    state_file=$(self_check_state_file_path)
    mkdir -p "$(dirname "$state_file")"
    chmod 750 "$(dirname "$state_file")" 2> /dev/null || true
    self_check_backup_file "$state_file"
    printf '%s\n' "$state_json" | self_check_atomic_write "$state_file" 0640 || return 1
    chown "root:${XRAY_GROUP}" "$state_file" 2> /dev/null || true
}

self_check_read_state_json() {
    local state_file
    state_file=$(self_check_state_file_path)
    [[ -f "$state_file" ]] || return 1
    cat "$state_file"
}

self_check_status_summary_tsv() {
    local state_json
    state_json=$(self_check_read_state_json 2> /dev/null) || return 1
    jq -r '[
        (.verdict // "unknown"),
        (.action // "unknown"),
        (.checked_at // "unknown"),
        (.selected_variant.config_name // "n/a"),
        (.selected_variant.variant_key // "n/a"),
        (.selected_variant.mode // "n/a"),
        (.selected_variant.ip_family // "n/a"),
        (.selected_variant.latency_ms // 0 | tostring)
    ] | @tsv' <<< "$state_json"
}

self_check_post_action_verdict() {
    local action="${1:-action}"
    local state_file
    state_file=$(self_check_state_file_path)

    local verdict="OK"
    local -a reasons=()
    local runtime_ok=true
    local transport_probe_required=true
    local state_json=""
    local selected_variant='null'
    local attempted_variants='[]'

    if [[ ! -x "$XRAY_BIN" ]]; then
        verdict="BROKEN"
        runtime_ok=false
        reasons+=("бинарник xray не найден: ${XRAY_BIN}")
    fi
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        verdict="BROKEN"
        runtime_ok=false
        reasons+=("конфиг не найден: ${XRAY_CONFIG}")
    fi
    if [[ "$runtime_ok" == true ]] && declare -F xray_config_test_ok > /dev/null 2>&1; then
        if ! xray_config_test_ok "$XRAY_CONFIG"; then
            verdict="BROKEN"
            runtime_ok=false
            reasons+=("xray -test отклонил текущий config.json")
        fi
    fi
    if [[ "$runtime_ok" == true ]] && declare -F systemctl_available > /dev/null 2>&1 && declare -F systemd_running > /dev/null 2>&1; then
        if systemctl_available && systemd_running; then
            if ! systemctl is-active --quiet xray 2> /dev/null; then
                verdict="BROKEN"
                runtime_ok=false
                reasons+=("systemd unit xray не active")
            fi
        else
            transport_probe_required=false
            if [[ "$verdict" != "BROKEN" ]]; then
                verdict="WARNING"
            fi
            reasons+=("systemd недоступен: transport-aware self-check пропущен")
        fi
    fi

    local json_file="${XRAY_KEYS}/clients.json"
    if [[ "$runtime_ok" == true && "$transport_probe_required" == true ]]; then
        if [[ ! -f "$json_file" ]]; then
            verdict="BROKEN"
            reasons+=("clients.json не найден: ${json_file}")
        elif ! jq -e 'type == "object" and (.configs | type == "array") and (.configs | length) >= 1' "$json_file" > /dev/null 2>&1; then
            verdict="BROKEN"
            reasons+=("clients.json повреждён или пуст")
        else
            local primary_recommended_variant
            primary_recommended_variant=$(jq -r '.configs[0].recommended_variant // "recommended"' "$json_file" 2> /dev/null)
            local config_index
            while IFS= read -r config_index; do
                config_index=${config_index//$'\r'/}
                config_index=$(self_check_trim_ws "$config_index")
                [[ "$config_index" =~ ^[0-9]+$ ]] || continue
                local variant_key
                while IFS= read -r variant_key; do
                    variant_key=${variant_key//$'\r'/}
                    variant_key=$(self_check_trim_ws "$variant_key")
                    [[ -n "$variant_key" ]] || continue

                    local job_json=""
                    job_json=$(self_check_config_job_json "$json_file" "$config_index" "$variant_key")
                    [[ -n "$job_json" ]] || continue

                    local raw_pair=""
                    if ! raw_pair=$(self_check_first_raw_file_for_job "$job_json"); then
                        local probe_result
                        probe_result=$(jq -n \
                            --arg action "$action" \
                            --arg config_name "$(jq -r '.config_name' <<< "$job_json")" \
                            --arg variant_key "$variant_key" \
                            --arg mode "$(jq -r '.mode' <<< "$job_json")" \
                            '{
                                checked_at: now | todateiso8601,
                                action: $action,
                                config_name: $config_name,
                                variant_key: $variant_key,
                                mode: (if ($mode | length) > 0 then $mode else null end),
                                ip_family: "n/a",
                                raw_config_file: null,
                                success: false,
                                latency_ms: 0,
                                selected_url: null,
                                reason: "raw_variant_file_missing",
                                probe_results: []
                            }')
                        attempted_variants=$(jq --argjson item "$probe_result" '. + [$item]' <<< "$attempted_variants")
                        continue
                    fi

                    local ip_family raw_file
                    IFS=$'\t' read -r ip_family raw_file <<< "$raw_pair"
                    local probe_result
                    probe_result=$(self_check_run_variant_probe \
                        "$action" \
                        "$(jq -r '.config_name' <<< "$job_json")" \
                        "$variant_key" \
                        "$(jq -r '.mode' <<< "$job_json")" \
                        "$ip_family" \
                        "$raw_file")
                    attempted_variants=$(jq --argjson item "$probe_result" '. + [$item]' <<< "$attempted_variants")

                    if jq -e '.success == true' <<< "$probe_result" > /dev/null 2>&1; then
                        selected_variant="$probe_result"
                        if [[ "$config_index" == "0" ]]; then
                            if [[ "$variant_key" != "$primary_recommended_variant" && "$verdict" != "BROKEN" ]]; then
                                verdict="WARNING"
                                reasons+=("recommended-вариант не прошёл self-check; используем rescue")
                            fi
                        else
                            if [[ "$verdict" != "BROKEN" ]]; then
                                verdict="WARNING"
                            fi
                            if [[ "$variant_key" == "rescue" ]]; then
                                reasons+=("primary-конфиг не прошёл self-check; используем запасной rescue-вариант $(jq -r '.config_name' <<< "$job_json")")
                            else
                                reasons+=("primary-конфиг не прошёл self-check; используем запасной конфиг $(jq -r '.config_name' <<< "$job_json")")
                            fi
                        fi
                        break 2
                    fi
                done < <(self_check_preferred_variant_keys "$json_file" "$config_index")
            done < <(jq -r '.configs | keys[]' "$json_file" 2> /dev/null)

            if [[ "$selected_variant" == "null" ]]; then
                verdict="BROKEN"
                reasons+=("ни recommended, ни rescue не прошли transport-aware self-check")
            fi
        fi
    fi

    state_json=$(jq -n \
        --arg checked_at "$(self_check_now_utc)" \
        --arg action "$action" \
        --arg verdict "$verdict" \
        --arg state_file "$state_file" \
        --argjson selected_variant "$selected_variant" \
        --argjson attempted_variants "$attempted_variants" \
        --argjson reasons "$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)" \
        --argjson systemd_ready "$(if declare -F systemctl_available > /dev/null 2>&1 && declare -F systemd_running > /dev/null 2>&1 && systemctl_available && systemd_running; then echo true; else echo false; fi)" \
        '{
            checked_at: $checked_at,
            action: $action,
            verdict: ($verdict | ascii_downcase),
            selected_variant: $selected_variant,
            attempted_variants: $attempted_variants,
            reasons: $reasons,
            systemd_ready: $systemd_ready,
            state_file: $state_file
        }')

    self_check_write_state_json "$state_json" || self_check_log WARN "не удалось сохранить self-check state"

    echo ""
    case "$verdict" in
        OK)
            self_check_log OK "self-check verdict (${action}): ok"
            ;;
        WARNING)
            self_check_log WARN "self-check verdict (${action}): warning"
            ;;
        *)
            self_check_log ERROR "self-check verdict (${action}): broken"
            ;;
    esac
    local reason
    for reason in "${reasons[@]}"; do
        [[ -n "$reason" ]] || continue
        echo "  - ${reason}"
    done
    if [[ "$selected_variant" != "null" ]]; then
        echo "  - selected variant: $(jq -r '.config_name' <<< "$selected_variant") / $(jq -r '.variant_key' <<< "$selected_variant") / $(jq -r '.ip_family' <<< "$selected_variant") / $(jq -r '(.latency_ms // 0 | tostring) + \"ms\"' <<< "$selected_variant")"
    fi
    echo ""

    [[ "$verdict" != "BROKEN" ]]
}
