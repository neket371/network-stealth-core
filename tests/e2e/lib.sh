#!/usr/bin/env bash
set -Eeuo pipefail

run_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
        return $?
    fi

    if command -v sudo > /dev/null 2>&1; then
        if sudo -n true > /dev/null 2>&1; then
            sudo -n "$@"
            return $?
        fi
        sudo "$@"
        return $?
    fi
    "$@"
}

cleanup_installation() {
    local script_path="$1"
    run_root bash "$script_path" uninstall --yes --non-interactive > /dev/null 2>&1 || true
}

assert_service_active() {
    local unit="$1"
    if ! run_root systemctl is-active --quiet "$unit"; then
        echo "service is not active: $unit" >&2
        run_root systemctl status "$unit" --no-pager -l >&2 || true
        exit 1
    fi
}

assert_path_mode_owner() {
    local path="$1"
    local expected_owner="$2"
    local expected_group="$3"
    local expected_mode="$4"

    if ! run_root test -e "$path"; then
        echo "expected path is missing: ${path}" >&2
        exit 1
    fi

    local actual
    actual="$(run_root stat -c '%U:%G:%a' "$path")"
    if [[ "$actual" != "${expected_owner}:${expected_group}:${expected_mode}" ]]; then
        echo "unexpected ownership or mode for ${path}: got ${actual}, expected ${expected_owner}:${expected_group}:${expected_mode}" >&2
        exit 1
    fi
}

assert_unit_journal_lacks() {
    local unit="$1"
    local pattern="$2"
    if run_root journalctl -u "$unit" --no-pager -n 200 2> /dev/null | grep -Eqi "$pattern"; then
        echo "unexpected journal pattern for ${unit}: ${pattern}" >&2
        run_root journalctl -u "$unit" --no-pager -n 200 >&2 || true
        exit 1
    fi
}

assert_xray_runtime_logs_contract() {
    local logs_dir="${XRAY_LOGS:-/var/log/xray}"
    assert_path_mode_owner "$logs_dir" xray xray 750
    assert_path_mode_owner "${logs_dir%/}/access.log" xray xray 640
    assert_path_mode_owner "${logs_dir%/}/error.log" xray xray 640
}

restart_xray_and_assert_healthy() {
    run_root systemctl restart xray
    assert_service_active xray
    run_root "${XRAY_BIN:-/usr/local/bin/xray}" run -test -config "${XRAY_CONFIG:-/etc/xray/config.json}" > /dev/null
    assert_xray_runtime_logs_contract
    assert_unit_journal_lacks xray 'permission denied|failed to initialize access logger'
}

force_rotate_xray_logs_and_assert_healthy() {
    run_root logrotate -f /etc/logrotate.d/xray
    restart_xray_and_assert_healthy
}

assert_path_absent() {
    local path="$1"
    if [[ -e "$path" ]]; then
        echo "path still exists: $path" >&2
        exit 1
    fi
}

assert_port_not_listening() {
    local port="$1"
    if run_root ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
        echo "port still listening: ${port}" >&2
        exit 1
    fi
}

assert_port_listening() {
    local port="$1"
    if ! run_root ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
        echo "expected listening port: ${port}" >&2
        exit 1
    fi
}

assert_user_absent() {
    local user_name="$1"
    if id "$user_name" > /dev/null 2>&1; then
        echo "user still exists: ${user_name}" >&2
        exit 1
    fi
}

collect_ports_from_config() {
    local config_path="$1"
    run_root jq -r '.inbounds[].port // empty' "$config_path" | sort -n -u
}

hash_as_root() {
    local file="$1"
    run_root sha256sum "$file" | awk '{print $1}'
}

assert_clients_json_xhttp_contract() {
    local json_path="$1"
    local expected_count="$2"

    # shellcheck disable=SC2016
    if ! run_root jq -e --argjson expected "$expected_count" '
        .schema_version == 3
        and .transport == "xhttp"
        and ((.configs | length) == $expected)
        and ([.configs[] |
            (.transport == "xhttp")
            and (.recommended_variant == "recommended")
            and (.flow == "xtls-rprx-vision")
            and (.vless_encryption != "none")
            and ((.variants | length) == 3)
            and (([.variants[].key] | sort) == ["emergency", "recommended", "rescue"])
            and (([.variants[].mode] | sort) == ["auto", "packet-up", "stream-up"])
            and (([.variants[].xray_client_file_v4 // empty] | length) == 3)
            and (([.variants[] | select(.key == "emergency") | .requires.browser_dialer] | all) == true)
        ] | all)
    ' "$json_path" > /dev/null; then
        echo "xhttp clients.json contract check failed: ${json_path}" >&2
        run_root jq '.' "$json_path" >&2 || true
        exit 1
    fi
}

assert_clients_json_legacy_contract() {
    local json_path="$1"
    local expected_count="$2"
    local transport="$3"

    # shellcheck disable=SC2016
    if ! run_root jq -e --argjson expected "$expected_count" --arg transport "$transport" '
        .schema_version == 2
        and .transport == $transport
        and ((.configs | length) == $expected)
        and ([.configs[] |
            (.transport == $transport)
            and (.recommended_variant == "standard")
            and ((.variants | length) == 1)
            and (.variants[0].key == "standard")
            and (((.variants[0].mode // "") | length) == 0)
            and (((.variants[0].xray_client_file_v4 // "") | length) == 0)
        ] | all)
    ' "$json_path" > /dev/null; then
        echo "legacy clients.json contract check failed: ${json_path}" >&2
        run_root jq '.' "$json_path" >&2 || true
        exit 1
    fi
}

assert_raw_xray_exports_exist() {
    local json_path="$1"
    local raw_file=""
    local found_any=false

    while IFS= read -r raw_file; do
        [[ -n "$raw_file" ]] || continue
        found_any=true
        if ! run_root test -f "$raw_file"; then
            echo "missing raw xray export: ${raw_file}" >&2
            exit 1
        fi
    done < <(run_root jq -r '.configs[] | .variants[] | .xray_client_file_v4 // empty, .xray_client_file_v6 // empty' "$json_path")

    if [[ "$found_any" != true ]]; then
        echo "no raw xray exports declared in ${json_path}" >&2
        exit 1
    fi
}
