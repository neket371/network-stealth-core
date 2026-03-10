#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"

START_PORT="${START_PORT:-24440}"
INITIAL_CONFIGS="${INITIAL_CONFIGS:-2}"
ADD_CONFIGS="${ADD_CONFIGS:-1}"
INSTALL_VERSION="${INSTALL_VERSION:-}"
UPDATE_VERSION="${UPDATE_VERSION:-}"
E2E_SERVER_IP="${E2E_SERVER_IP:-127.0.0.1}"
E2E_DOMAIN_CHECK="${E2E_DOMAIN_CHECK:-false}"
E2E_SKIP_REALITY_CHECK="${E2E_SKIP_REALITY_CHECK:-true}"
E2E_ALLOW_INSECURE_SHA256="${E2E_ALLOW_INSECURE_SHA256:-true}"
E2E_KEEP_FAILURE_STATE="${E2E_KEEP_FAILURE_STATE:-false}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/config.json}"
XRAY_KEYS_DIR="${XRAY_KEYS_DIR:-/etc/xray/private/keys}"
KEYS_FILE="${XRAY_KEYS_DIR}/keys.txt"
CLIENTS_FILE="${XRAY_KEYS_DIR}/clients.txt"
CLIENTS_JSON="${XRAY_KEYS_DIR}/clients.json"
STATUS_FILE="/tmp/xru-nightly-status.txt"

require_vm_systemd() {
    local pid1
    pid1="$(ps -p 1 -o comm= | tr -d '[:space:]')"
    if [[ "$pid1" != "systemd" ]]; then
        echo "nightly vm gate requires pid1=systemd, got: ${pid1}" >&2
        return 1
    fi

    if ! run_root systemctl list-unit-files > /dev/null 2>&1; then
        echo "systemctl is not available in this runner" >&2
        return 1
    fi
    return 0
}

resolve_version_pair() {
    local api_url="${XRAY_RELEASES_API:-https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5}"
    local releases_json
    local latest_tag
    local previous_tag

    releases_json="$(curl --fail --show-error --silent --location "$api_url" 2> /dev/null || true)"
    [[ -n "$releases_json" ]] || return 0

    latest_tag="$(jq -r '[.[] | select((.draft | not) and (.prerelease | not))][0].tag_name // empty' <<< "$releases_json" | sed 's/^v//')"
    previous_tag="$(jq -r '[.[] | select((.draft | not) and (.prerelease | not))][1].tag_name // empty' <<< "$releases_json" | sed 's/^v//')"

    if [[ -n "$latest_tag" && -n "$previous_tag" && "$latest_tag" != "$previous_tag" ]]; then
        if [[ -z "$INSTALL_VERSION" ]]; then
            INSTALL_VERSION="$previous_tag"
        fi
        if [[ -z "$UPDATE_VERSION" ]]; then
            UPDATE_VERSION="$latest_tag"
        fi
    fi
}

hash_file() {
    local file="$1"
    hash_as_root "$file"
}

latest_backup_dir() {
    run_root find /var/backups/xray -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' |
        sort -nr |
        head -n 1 |
        awk '{print $2}'
}

xray_version() {
    local raw version
    raw="$(run_root "$XRAY_BIN" version 2> /dev/null || true)"
    version="$(awk '/^Xray /{print $2; exit}' <<< "$raw")"
    version="${version#v}"
    printf '%s\n' "$version"
}

cleanup_state() {
    cleanup_installation "$SCRIPT_PATH"
    rm -f "$STATUS_FILE"
}

cleanup_on_exit() {
    local exit_code=$?
    if ((exit_code != 0)) && [[ "$E2E_KEEP_FAILURE_STATE" == "true" ]]; then
        echo "==> keeping failed lifecycle state for inspection"
        rm -f "$STATUS_FILE"
        return 0
    fi
    cleanup_state
}

trap cleanup_on_exit EXIT

echo "==> pre-clean"
cleanup_state

echo "==> verify vm systemd runtime"
if ! require_vm_systemd; then
    echo "nightly vm gate: skipping lifecycle smoke on non-systemd runner"
    trap - EXIT
    exit 0
fi

echo "==> resolve xray version pair (install->update)"
resolve_version_pair
if [[ -n "$INSTALL_VERSION" ]]; then
    echo "using install version: $INSTALL_VERSION"
fi
if [[ -n "$UPDATE_VERSION" ]]; then
    echo "using update version: $UPDATE_VERSION"
fi

echo "==> install"
install_env=(
    NON_INTERACTIVE=true
    ASSUME_YES=true
    XRAY_NUM_CONFIGS="$INITIAL_CONFIGS"
    START_PORT="$START_PORT"
    SERVER_IP="$E2E_SERVER_IP"
    DOMAIN_CHECK="$E2E_DOMAIN_CHECK"
    SKIP_REALITY_CHECK="$E2E_SKIP_REALITY_CHECK"
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256"
)
if [[ -n "$INSTALL_VERSION" ]]; then
    install_env+=(XRAY_VERSION="$INSTALL_VERSION")
fi
run_root env \
    "${install_env[@]}" \
    bash "$SCRIPT_PATH" install

echo "==> add-clients"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256" \
    bash "$SCRIPT_PATH" add-clients "$ADD_CONFIGS"

assert_service_active xray

echo "==> repair"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256" \
    bash "$SCRIPT_PATH" repair

assert_service_active xray

for file in "$XRAY_CONFIG" "$KEYS_FILE" "$CLIENTS_FILE" "$CLIENTS_JSON"; do
    if ! run_root test -f "$file"; then
        echo "missing expected file before update: $file" >&2
        exit 1
    fi
done

declare -A baseline_sha=()
for file in "$XRAY_CONFIG" "$KEYS_FILE" "$CLIENTS_FILE" "$CLIENTS_JSON"; do
    baseline_sha["$file"]="$(hash_file "$file")"
done

version_before="$(xray_version)"

echo "==> update"
update_env=(
    NON_INTERACTIVE=true
    ASSUME_YES=true
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256"
)
if [[ -n "$UPDATE_VERSION" ]]; then
    update_env+=(
        XRAY_VERSION="$UPDATE_VERSION"
        XRAY_CONFIG_FILE=/dev/null
    )
fi
run_root env \
    "${update_env[@]}" \
    bash "$SCRIPT_PATH" update

assert_service_active xray
version_after="$(xray_version)"
if [[ -n "$INSTALL_VERSION" && -n "$UPDATE_VERSION" && "$INSTALL_VERSION" != "$UPDATE_VERSION" ]]; then
    if [[ "$version_after" != "$UPDATE_VERSION" ]]; then
        echo "expected xray version after update=$UPDATE_VERSION, got=$version_after" >&2
        exit 1
    fi
    if [[ "$version_before" == "$version_after" ]]; then
        echo "expected version transition, but stayed on $version_after" >&2
        exit 1
    fi
fi

backup_dir="$(latest_backup_dir)"
if [[ -z "$backup_dir" ]]; then
    echo "backup directory not found after update" >&2
    exit 1
fi

for file in "$XRAY_CONFIG" "$KEYS_FILE" "$CLIENTS_FILE" "$CLIENTS_JSON"; do
    rel_path="${file#/}"
    if ! run_root test -f "${backup_dir}/${rel_path}"; then
        echo "backup is missing expected artifact: ${backup_dir}/${rel_path}" >&2
        exit 1
    fi
done

echo "==> tamper runtime artifacts"
run_root bash -c "printf '%s\n' 'tampered-keys' > '$KEYS_FILE'"
run_root bash -c "printf '%s\n' 'tampered-clients' > '$CLIENTS_FILE'"
run_root bash -c "printf '%s\n' '{\"tampered\":true}' > '$CLIENTS_JSON'"
run_root bash -c "printf '%s\n' '{\"log\":{\"loglevel\":\"warning\"},\"inbounds\":[],\"outbounds\":[{\"protocol\":\"freedom\"}],\"routing\":{\"rules\":[]}}' > '$XRAY_CONFIG'"
run_root systemctl stop xray > /dev/null 2>&1 || true

echo "==> rollback from update backup"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    bash "$SCRIPT_PATH" rollback "$backup_dir"
assert_service_active xray

echo "==> verify rollback restored original artifacts"
for file in "$XRAY_CONFIG" "$KEYS_FILE" "$CLIENTS_FILE" "$CLIENTS_JSON"; do
    current_sha="$(hash_file "$file")"
    if [[ "$current_sha" != "${baseline_sha[$file]}" ]]; then
        echo "hash mismatch after rollback for $file" >&2
        echo "expected: ${baseline_sha[$file]}" >&2
        echo "got:      $current_sha" >&2
        exit 1
    fi
done

echo "==> status"
run_root bash "$SCRIPT_PATH" status --verbose > "$STATUS_FILE"
grep -q "Inbounds:" "$STATUS_FILE"

inbound_count="$(run_root jq '.inbounds | length' "$XRAY_CONFIG")"
expected_min=$((INITIAL_CONFIGS + ADD_CONFIGS))
if ((inbound_count < expected_min)); then
    echo "Expected at least ${expected_min} inbounds, got ${inbound_count}" >&2
    exit 1
fi

mapfile -t ports_before_uninstall < <(run_root jq -r '.inbounds[].port // empty' "$XRAY_CONFIG" | sort -n -u)
if [[ ${#ports_before_uninstall[@]} -eq 0 ]]; then
    echo "No ports detected before uninstall" >&2
    exit 1
fi

echo "==> uninstall"
run_root bash "$SCRIPT_PATH" uninstall --yes --non-interactive

echo "==> post-checks"
assert_path_absent /etc/xray
assert_path_absent /etc/xray-reality
assert_path_absent /usr/local/bin/xray
assert_path_absent /usr/local/bin/xray-reality.sh

for port in "${ports_before_uninstall[@]}"; do
    assert_port_not_listening "$port"
done

assert_user_absent xray

trap - EXIT
echo "e2e nightly smoke lifecycle check passed."
