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

self_check_history_file_path() {
    local state_file
    state_file=$(self_check_state_file_path)
    if [[ -n "${SELF_CHECK_HISTORY_FILE:-}" && ! ("${SELF_CHECK_HISTORY_FILE:-}" == "/var/lib/xray/self-check-history.ndjson" && "$(dirname "$state_file")" != "/var/lib/xray") ]]; then
        printf '%s\n' "$SELF_CHECK_HISTORY_FILE"
        return 0
    fi
    printf '%s\n' "$(dirname "$state_file")/self-check-history.ndjson"
}

self_check_ensure_private_storage_dir() {
    local dir="${1:-}"
    local existed=false

    [[ -n "$dir" ]] || return 1
    if [[ -d "$dir" ]]; then
        existed=true
    fi

    mkdir -p "$dir" || return 1
    if [[ "$existed" != true ]]; then
        chmod 750 "$dir" 2> /dev/null || true
    fi
}

self_check_default_urls() {
    printf '%s\n' "${SELF_CHECK_URLS:-https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204}"
}

self_check_is_loopback_runtime() {
    local ipv4="${SERVER_IP:-}"
    local ipv6="${SERVER_IP6:-}"

    ipv4=$(self_check_trim_ws "$ipv4")
    ipv6=$(self_check_trim_ws "$ipv6")

    case "$ipv4" in
        127.0.0.1 | localhost)
            return 0
            ;;
        *) ;;
    esac

    case "$ipv6" in
        ::1 | "[::1]" | localhost)
            return 0
            ;;
        *) ;;
    esac

    return 1
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
    local candidate
    local tries_left=64
    while ((tries_left > 0)); do
        candidate=$((base + RANDOM % span))
        if ! self_check_port_is_listening "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
        tries_left=$((tries_left - 1))
    done

    for ((candidate = base; candidate <= base + span; candidate++)); do
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

self_check_wait_for_process_exit() {
    local pid="${1:-}"
    local attempts="${2:-20}"
    local sleep_interval="${3:-0.1}"
    local process_state=""

    [[ "$pid" =~ ^[0-9]+$ ]] || return 0

    while ((attempts > 0)); do
        if ! kill -0 "$pid" 2> /dev/null; then
            return 0
        fi
        if command -v ps > /dev/null 2>&1; then
            process_state=$(ps -o stat= -p "$pid" 2> /dev/null | tr -d '[:space:]')
            if [[ "$process_state" == Z* ]]; then
                return 0
            fi
        fi
        sleep "$sleep_interval"
        attempts=$((attempts - 1))
    done
    return 1
}

self_check_stop_client_process() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0

    if ! kill -0 "$pid" 2> /dev/null; then
        wait "$pid" 2> /dev/null || true
        return 0
    fi

    kill "$pid" 2> /dev/null || true
    if self_check_wait_for_process_exit "$pid" 20 0.1; then
        wait "$pid" 2> /dev/null || true
        return 0
    fi

    self_check_debug "self-check client pid ${pid} did not stop after sigterm; forcing sigkill"
    kill -9 "$pid" 2> /dev/null || true
    if self_check_wait_for_process_exit "$pid" 10 0.1; then
        wait "$pid" 2> /dev/null || true
        return 0
    fi

    self_check_debug "self-check client pid ${pid} remained after sigkill"
    return 1
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

self_check_run_variant_probe_skipped_json() {
    local action="$1"
    local config_name="$2"
    local variant_key="$3"
    local mode="$4"
    local ip_family="$5"
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
}

self_check_run_variant_probe_prepare_runtime() {
    local config_name="$1"
    local variant_key="$2"
    local raw_config_file="$3"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_tmp_dir="$4"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_runtime_config="$5"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_runtime_log="$6"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_proxy_port="$7"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_pid="$8"
    local out_reason_name="$9"

    if [[ ! -x "$XRAY_BIN" ]]; then
        printf -v "$out_reason_name" '%s' "xray_bin_missing"
        return 0
    fi
    if [[ ! -f "$raw_config_file" ]]; then
        printf -v "$out_reason_name" '%s' "raw_config_missing"
        return 0
    fi
    if ! out_proxy_port=$(self_check_pick_free_port); then
        printf -v "$out_reason_name" '%s' "no_free_local_proxy_port"
        return 0
    fi
    out_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/xray-self-check.XXXXXX") || {
        printf -v "$out_reason_name" '%s' "tmpdir_create_failed"
        return 0
    }

    out_runtime_config="${out_tmp_dir}/client.json"
    out_runtime_log="${out_tmp_dir}/client.log"
    if ! self_check_prepare_runtime_config "$raw_config_file" "$out_proxy_port" "$out_runtime_config"; then
        printf -v "$out_reason_name" '%s' "runtime_config_prepare_failed"
        return 0
    fi

    if declare -F xray_config_test_ok > /dev/null 2>&1; then
        if ! xray_config_test_ok "$out_runtime_config" > /dev/null 2>&1; then
            printf -v "$out_reason_name" '%s' "runtime_config_test_failed"
            return 0
        fi
    fi

    out_pid=$(self_check_start_client_process "$out_runtime_config" "$out_runtime_log")
    if [[ -z "$out_pid" ]]; then
        printf -v "$out_reason_name" '%s' "client_start_failed"
        return 0
    fi
    if ! self_check_wait_for_proxy "$out_proxy_port"; then
        printf -v "$out_reason_name" '%s' "proxy_not_ready"
        local runtime_tail=""
        runtime_tail=$(tail -n 20 "$out_runtime_log" 2> /dev/null || true)
        self_check_debug "self-check proxy failed to start for ${config_name}/${variant_key}; log=${runtime_tail}"
    fi
}

self_check_run_variant_probe_execute_urls() {
    local proxy_port="$1"
    # shellcheck disable=SC2034 # Used as nameref output parameter.
    local -n out_probe_results="$2"
    local out_selected_url_name="$3"
    local out_best_latency_ms_name="$4"
    local out_success_name="$5"
    local out_reason_name="$6"
    local urls_json='[]'

    urls_json=$(self_check_urls_json)
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        local single_result=""
        single_result=$(self_check_probe_single_url "$proxy_port" "$url" "${SELF_CHECK_TIMEOUT_SEC:-8}")
        out_probe_results=$(jq --argjson item "$single_result" '. + [$item]' <<< "$out_probe_results")
    done < <(jq -r '.[]' <<< "$urls_json")

    if jq -e 'any(.[]; .success == true)' <<< "$out_probe_results" > /dev/null 2>&1; then
        printf -v "$out_success_name" '%s' true
        printf -v "$out_selected_url_name" '%s' "$(jq -r '[.[] | select(.success == true)] | sort_by(.latency_ms) | .[0].url // ""' <<< "$out_probe_results")"
        printf -v "$out_best_latency_ms_name" '%s' "$(jq -r '[.[] | select(.success == true)] | sort_by(.latency_ms) | .[0].latency_ms // 0' <<< "$out_probe_results")"
    else
        printf -v "$out_reason_name" '%s' "$(jq -r '[.[] | .error // ("http_" + .http_code)] | map(select(length > 0)) | first // "probe_failed"' <<< "$out_probe_results")"
    fi
}

self_check_run_variant_probe_result_json() {
    local action="$1"
    local config_name="$2"
    local variant_key="$3"
    local mode="$4"
    local ip_family="$5"
    local raw_config_file="$6"
    local selected_url="$7"
    local reason="$8"
    local success="$9"
    local latency_ms="${10}"
    local probe_results="${11}"

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
        --argjson latency_ms "${latency_ms:-0}" \
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

self_check_run_variant_probe() {
    local action="$1"
    local config_name="$2"
    local variant_key="$3"
    local mode="$4"
    local ip_family="$5"
    local raw_config_file="$6"
    local tmp_dir=""
    # shellcheck disable=SC2034 # Used via nameref helper.
    local runtime_config=""
    # shellcheck disable=SC2034 # Used via nameref helper.
    local runtime_log=""
    local proxy_port=""
    local pid=""
    local reason=""
    local probe_results='[]'
    local selected_url=""
    local best_latency_ms=0
    local success=false

    if [[ "${SELF_CHECK_ENABLED:-true}" != "true" ]]; then
        self_check_run_variant_probe_skipped_json "$action" "$config_name" "$variant_key" "$mode" "$ip_family"
        return 0
    fi

    self_check_run_variant_probe_prepare_runtime \
        "$config_name" "$variant_key" "$raw_config_file" \
        tmp_dir runtime_config runtime_log proxy_port pid reason

    if [[ -z "$reason" ]]; then
        self_check_run_variant_probe_execute_urls \
            "$proxy_port" probe_results selected_url best_latency_ms success reason
    fi

    if ! self_check_stop_client_process "$pid"; then
        self_check_debug "self-check cleanup failed for ${config_name}/${variant_key}; pid=${pid}"
        if [[ -z "$reason" ]]; then
            reason="client_stop_timeout"
            success=false
            selected_url=""
            best_latency_ms=0
        fi
    fi
    [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"

    self_check_run_variant_probe_result_json \
        "$action" "$config_name" "$variant_key" "$mode" "$ip_family" \
        "$raw_config_file" "$selected_url" "$reason" "$success" "${best_latency_ms:-0}" "$probe_results"
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
    self_check_ensure_private_storage_dir "$(dirname "$state_file")" || return 1
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

self_check_append_history_json() {
    local state_json="$1"
    local history_file
    history_file=$(self_check_history_file_path)
    self_check_ensure_private_storage_dir "$(dirname "$history_file")" || return 1
    self_check_backup_file "$history_file"
    touch "$history_file"
    chmod 640 "$history_file" 2> /dev/null || true
    printf '%s\n' "$(jq -c '.' <<< "$state_json")" >> "$history_file"
    chown "root:${XRAY_GROUP}" "$history_file" 2> /dev/null || true
}

self_check_recent_history_json() {
    local limit="${1:-5}"
    local history_file
    history_file=$(self_check_history_file_path)
    [[ -f "$history_file" ]] || {
        printf '%s\n' '[]'
        return 0
    }
    tail -n "$limit" "$history_file" 2> /dev/null | jq -s '.' 2> /dev/null || printf '%s\n' '[]'
}

self_check_warning_streak_count() {
    local history_json
    history_json=$(self_check_recent_history_json 2)
    jq -r '
        if length < 2 then 0
        elif (.[-1].verdict == "warning" and .[-2].verdict == "warning") then 2
        elif (.[-1].verdict == "warning") then 1
        else 0
        end
    ' <<< "$history_json"
}

self_check_last_verdict() {
    local history_json
    history_json=$(self_check_recent_history_json 1)
    jq -r '.[-1].verdict // "unknown"' <<< "$history_json"
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

self_check_post_action_runtime_preflight() {
    local verdict_name="$1"
    local runtime_ok_name="$2"
    local transport_probe_required_name="$3"
    local reasons_name="$4"
    local -n verdict_ref="$verdict_name"
    local -n runtime_ok_ref="$runtime_ok_name"
    local -n transport_probe_required_ref="$transport_probe_required_name"
    # shellcheck disable=SC2178 # reasons_ref intentionally aliases an array in the caller.
    local -n reasons_ref="$reasons_name"

    if [[ ! -x "$XRAY_BIN" ]]; then
        verdict_ref="BROKEN"
        runtime_ok_ref=false
        reasons_ref+=("бинарник xray не найден: ${XRAY_BIN}")
    fi
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        verdict_ref="BROKEN"
        runtime_ok_ref=false
        reasons_ref+=("конфиг не найден: ${XRAY_CONFIG}")
    fi
    if [[ "$runtime_ok_ref" == true ]] && declare -F xray_config_test_ok > /dev/null 2>&1; then
        if ! xray_config_test_ok "$XRAY_CONFIG"; then
            verdict_ref="BROKEN"
            runtime_ok_ref=false
            reasons_ref+=("xray -test отклонил текущий config.json")
        fi
    fi
    if [[ "$runtime_ok_ref" == true ]] && declare -F systemctl_available > /dev/null 2>&1 && declare -F systemd_running > /dev/null 2>&1; then
        if systemctl_available && systemd_running; then
            if ! systemctl is-active --quiet xray 2> /dev/null; then
                verdict_ref="BROKEN"
                runtime_ok_ref=false
                reasons_ref+=("systemd unit xray не active")
            fi
        elif self_check_is_loopback_runtime; then
            transport_probe_required_ref=false
            if [[ "$verdict_ref" != "BROKEN" ]]; then
                verdict_ref="WARNING"
            fi
            reasons_ref+=("loopback install detected: transport-aware self-check пропущен")
        else
            transport_probe_required_ref=false
            if [[ "$verdict_ref" != "BROKEN" ]]; then
                verdict_ref="WARNING"
            fi
            reasons_ref+=("systemd недоступен: transport-aware self-check пропущен")
        fi
    fi
    if [[ "$runtime_ok_ref" == true && "$transport_probe_required_ref" == true ]] && self_check_is_loopback_runtime; then
        transport_probe_required_ref=false
        if [[ "$verdict_ref" != "BROKEN" ]]; then
            verdict_ref="WARNING"
        fi
        reasons_ref+=("loopback install detected: transport-aware self-check пропущен")
    fi
}

self_check_post_action_missing_raw_probe_result() {
    local action="$1"
    local job_json="$2"
    local variant_key="$3"
    jq -n \
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
        }'
}

self_check_post_action_probe_variants() {
    local action="$1"
    local json_file="$2"
    local verdict_name="$3"
    local runtime_ok_name="$4"
    local transport_probe_required_name="$5"
    local reasons_name="$6"
    local selected_variant_name="$7"
    local attempted_variants_name="$8"
    local -n verdict_ref="$verdict_name"
    local -n runtime_ok_ref="$runtime_ok_name"
    local -n transport_probe_required_ref="$transport_probe_required_name"
    # shellcheck disable=SC2178 # reasons_ref intentionally aliases an array in the caller.
    local -n reasons_ref="$reasons_name"
    local -n selected_variant_ref="$selected_variant_name"
    local -n attempted_variants_ref="$attempted_variants_name"

    if [[ "$runtime_ok_ref" != true || "$transport_probe_required_ref" != true ]]; then
        return 0
    fi
    if [[ ! -f "$json_file" ]]; then
        verdict_ref="BROKEN"
        reasons_ref+=("clients.json не найден: ${json_file}")
        return 0
    fi
    if ! jq -e 'type == "object" and (.configs | type == "array") and (.configs | length) >= 1' "$json_file" > /dev/null 2>&1; then
        verdict_ref="BROKEN"
        reasons_ref+=("clients.json повреждён или пуст")
        return 0
    fi

    self_check_log STEP "transport-aware self-check: проверяем exported client variants..."
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
                local probe_result=""
                probe_result=$(self_check_post_action_missing_raw_probe_result "$action" "$job_json" "$variant_key")
                attempted_variants_ref=$(jq --argjson item "$probe_result" '. + [$item]' <<< "$attempted_variants_ref")
                continue
            fi

            local ip_family raw_file
            IFS=$'\t' read -r ip_family raw_file <<< "$raw_pair"
            self_check_log INFO "self-check: $(jq -r '.config_name' <<< "$job_json") / ${variant_key} / ${ip_family}"

            local probe_result
            probe_result=$(self_check_run_variant_probe \
                "$action" \
                "$(jq -r '.config_name' <<< "$job_json")" \
                "$variant_key" \
                "$(jq -r '.mode' <<< "$job_json")" \
                "$ip_family" \
                "$raw_file")
            attempted_variants_ref=$(jq --argjson item "$probe_result" '. + [$item]' <<< "$attempted_variants_ref")

            if jq -e '.success == true' <<< "$probe_result" > /dev/null 2>&1; then
                selected_variant_ref="$probe_result"
                if [[ "$config_index" == "0" ]]; then
                    if [[ "$variant_key" != "$primary_recommended_variant" && "$verdict_ref" != "BROKEN" ]]; then
                        verdict_ref="WARNING"
                        reasons_ref+=("recommended-вариант не прошёл self-check; используем rescue")
                    fi
                else
                    if [[ "$verdict_ref" != "BROKEN" ]]; then
                        verdict_ref="WARNING"
                    fi
                    if [[ "$variant_key" == "rescue" ]]; then
                        reasons_ref+=("primary-конфиг не прошёл self-check; используем запасной rescue-вариант $(jq -r '.config_name' <<< "$job_json")")
                    else
                        reasons_ref+=("primary-конфиг не прошёл self-check; используем запасной конфиг $(jq -r '.config_name' <<< "$job_json")")
                    fi
                fi
                return 0
            fi
        done < <(self_check_preferred_variant_keys "$json_file" "$config_index")
    done < <(jq -r '.configs | keys[]' "$json_file" 2> /dev/null)

    if [[ "$selected_variant_ref" == "null" ]]; then
        verdict_ref="BROKEN"
        reasons_ref+=("ни recommended, ни rescue не прошли transport-aware self-check")
    fi
}

self_check_post_action_build_state_json() {
    local action="$1"
    local state_file="$2"
    jq -n \
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
        }'
}

self_check_post_action_render_summary() {
    local action="$1"
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
        echo "  - selected variant: $(jq -r '.config_name' <<< "$selected_variant") / $(jq -r '.variant_key' <<< "$selected_variant") / $(jq -r '.ip_family' <<< "$selected_variant") / $(jq -r '(.latency_ms // 0 | tostring) + "ms"' <<< "$selected_variant")"
    fi
    echo ""
}

self_check_post_action_verdict() {
    local action="${1:-action}"
    local state_file
    state_file=$(self_check_state_file_path)

    local verdict="OK"
    local -a reasons=()
    # shellcheck disable=SC2034 # Mutated through explicit nameref helpers below.
    local runtime_ok=true
    # shellcheck disable=SC2034 # Mutated through explicit nameref helpers below.
    local transport_probe_required=true
    local state_json=""
    local selected_variant='null'
    local attempted_variants='[]'
    local json_file="${XRAY_KEYS}/clients.json"

    self_check_post_action_runtime_preflight \
        verdict runtime_ok transport_probe_required reasons
    self_check_post_action_probe_variants \
        "$action" "$json_file" \
        verdict runtime_ok transport_probe_required reasons selected_variant attempted_variants

    state_json=$(self_check_post_action_build_state_json "$action" "$state_file")
    self_check_write_state_json "$state_json" || self_check_log WARN "не удалось сохранить self-check state"
    self_check_append_history_json "$state_json" || self_check_log WARN "не удалось сохранить self-check history"
    self_check_post_action_render_summary "$action"

    [[ "$verdict" != "BROKEN" ]]
}
