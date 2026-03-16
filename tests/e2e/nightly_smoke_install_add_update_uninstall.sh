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
CLIENTS_LINKS_FILE="${XRAY_KEYS_DIR}/clients-links.txt"
CLIENTS_JSON="${XRAY_KEYS_DIR}/clients.json"
STATUS_FILE="$(mktemp /tmp/xru-nightly-status.XXXXXX)"
E2E_PROOF_DIR="${E2E_PROOF_DIR:-}"
declare -a PROOF_STEPS=()

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

proof_enabled() {
    [[ -n "${E2E_PROOF_DIR:-}" ]]
}

proof_prepare_dir() {
    proof_enabled || return 0
    mkdir -p "$E2E_PROOF_DIR"
}

proof_record_step() {
    proof_enabled || return 0
    PROOF_STEPS+=("${1}:ok")
}

proof_capture_optional_file() {
    local src="$1"
    local dest="$2"
    proof_enabled || return 0
    if run_root test -f "$src"; then
        run_root cat "$src" > "$dest"
    fi
}

proof_capture_runtime_evidence() {
    proof_enabled || return 0

    mkdir -p "$E2E_PROOF_DIR"
    run_root bash "$SCRIPT_PATH" status --verbose > "${E2E_PROOF_DIR}/status-verbose.txt"
    run_root bash "$SCRIPT_PATH" diagnose > "${E2E_PROOF_DIR}/diagnose.txt" || true

    proof_capture_optional_file "/var/lib/xray/self-check.json" "${E2E_PROOF_DIR}/self-check.json"
    proof_capture_optional_file "/var/lib/xray/measurements/latest-summary.json" "${E2E_PROOF_DIR}/measurement-summary.json"
    proof_capture_optional_file "${XRAY_KEYS_DIR}/export/capabilities.json" "${E2E_PROOF_DIR}/capabilities.json"
    proof_capture_optional_file "${XRAY_KEYS_DIR}/export/canary/manifest.json" "${E2E_PROOF_DIR}/canary-manifest.json"
    proof_capture_optional_file "/etc/xray-reality/custom-domains.txt" "${E2E_PROOF_DIR}/custom-domains.txt"

    local inventory_tsv="${E2E_PROOF_DIR}/artifact-inventory.tsv"
    : > "$inventory_tsv"

    local path mode size sha sensitive
    for path in \
        "$XRAY_CONFIG" \
        "/etc/xray-reality/config.env" \
        "/etc/xray-reality/custom-domains.txt" \
        "/etc/xray-reality/policy.json" \
        "$KEYS_FILE" \
        "$CLIENTS_FILE" \
        "$CLIENTS_LINKS_FILE" \
        "$CLIENTS_JSON" \
        "${XRAY_KEYS_DIR}/export/capabilities.json" \
        "${XRAY_KEYS_DIR}/export/raw-xray-index.json" \
        "${XRAY_KEYS_DIR}/export/canary/manifest.json" \
        "/var/lib/xray/self-check.json" \
        "/var/lib/xray/measurements/latest-summary.json"; do
        if ! run_root test -f "$path"; then
            continue
        fi
        mode="$(run_root stat -c '%a' "$path")"
        size="$(run_root stat -c '%s' "$path")"
        sha="$(run_root sha256sum "$path" | awk '{print $1}')"
        sensitive="false"
        case "$path" in
            "$XRAY_CONFIG" | "/etc/xray-reality/config.env" | "/etc/xray-reality/policy.json" | "$KEYS_FILE" | "$CLIENTS_FILE" | "$CLIENTS_LINKS_FILE" | "$CLIENTS_JSON" | "${XRAY_KEYS_DIR}/export/raw-xray-index.json")
                sensitive="true"
                ;;
            *)
                sensitive="false"
                ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$mode" "$size" "$sha" "$sensitive" >> "$inventory_tsv"
    done

    python3 - "$inventory_tsv" "${E2E_PROOF_DIR}/artifact-inventory.json" << 'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
items = []
if src.exists():
    for line in src.read_text(encoding="utf-8").splitlines():
        path, mode, size, sha256, sensitive = line.split("\t")
        items.append(
            {
                "path": path,
                "mode": mode,
                "size_bytes": int(size),
                "sha256": sha256,
                "contains_sensitive_material": sensitive == "true",
            }
        )
dst.write_text(json.dumps(items, indent=2) + "\n", encoding="utf-8")
PY
}

proof_capture_failure_evidence() {
    proof_enabled || return 0

    mkdir -p "$E2E_PROOF_DIR"

    run_root systemctl cat xray > "${E2E_PROOF_DIR}/failure-systemctl-cat-xray.txt" 2>&1 || true
    run_root systemctl show xray \
        -p User \
        -p Group \
        -p SupplementaryGroups \
        -p LogsDirectory \
        -p ReadWritePaths \
        -p FragmentPath \
        -p DropInPaths \
        > "${E2E_PROOF_DIR}/failure-systemctl-show-xray.txt" 2>&1 || true
    run_root systemctl status xray --no-pager -l > "${E2E_PROOF_DIR}/failure-systemctl-status-xray.txt" 2>&1 || true
    run_root journalctl -u xray --no-pager -n 200 > "${E2E_PROOF_DIR}/failure-journal-xray.txt" 2>&1 || true
    run_root journalctl -u xray-health --no-pager -n 200 > "${E2E_PROOF_DIR}/failure-journal-xray-health.txt" 2>&1 || true
    run_root bash -lc 'id xray' > "${E2E_PROOF_DIR}/failure-id-xray.txt" 2>&1 || true
    run_root bash -lc 'namei -l /var/log/xray/access.log' > "${E2E_PROOF_DIR}/failure-namei-access-log.txt" 2>&1 || true
    run_root bash -lc "stat -c '%U:%G:%a %n' /var/log /var/log/xray /var/log/xray/access.log /var/log/xray/error.log" \
        > "${E2E_PROOF_DIR}/failure-log-path-stats.txt" 2>&1 || true
    run_root bash -lc "test -f /etc/systemd/system/xray.service && cat /etc/systemd/system/xray.service" \
        > "${E2E_PROOF_DIR}/failure-unit-file.txt" 2>&1 || true
    run_root bash -lc "test -f /etc/logrotate.d/xray && cat /etc/logrotate.d/xray" \
        > "${E2E_PROOF_DIR}/failure-logrotate-xray.txt" 2>&1 || true
}

proof_write_lifecycle_manifest() {
    proof_enabled || return 0

    local steps_file="${E2E_PROOF_DIR}/lifecycle.json"
    python3 - "$steps_file" "$INSTALL_VERSION" "$UPDATE_VERSION" "$version_before" "$version_after" "$backup_dir" "${PROOF_STEPS[@]}" << 'PY'
import json
import sys
from pathlib import Path

dst = Path(sys.argv[1])
install_version = sys.argv[2] or None
update_version = sys.argv[3] or None
version_before = sys.argv[4] or None
version_after = sys.argv[5] or None
backup_dir = sys.argv[6] or None
steps = []
for item in sys.argv[7:]:
    name, status = item.split(":", 1)
    steps.append({"step": name, "status": status})

payload = {
    "install_version": install_version,
    "update_version": update_version,
    "version_before_update": version_before,
    "version_after_update": version_after,
    "rollback_source": backup_dir,
    "steps": steps,
}
dst.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
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
    if ((exit_code != 0)); then
        proof_capture_failure_evidence || true
    fi
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
proof_prepare_dir

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
    XRAY_FAILURE_PROOF_DIR="${E2E_PROOF_DIR:+${E2E_PROOF_DIR}/install-failure}"
)
if [[ -n "$INSTALL_VERSION" ]]; then
    install_env+=(XRAY_VERSION="$INSTALL_VERSION")
fi
run_root env \
    "${install_env[@]}" \
    bash "$SCRIPT_PATH" install
proof_record_step install
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy
force_rotate_xray_logs_and_assert_healthy

echo "==> add-clients"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256" \
    XRAY_FAILURE_PROOF_DIR="${E2E_PROOF_DIR:+${E2E_PROOF_DIR}/add-clients-failure}" \
    bash "$SCRIPT_PATH" add-clients "$ADD_CONFIGS"
proof_record_step add-clients

assert_service_active xray
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy

echo "==> repair"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256="$E2E_ALLOW_INSECURE_SHA256" \
    XRAY_FAILURE_PROOF_DIR="${E2E_PROOF_DIR:+${E2E_PROOF_DIR}/repair-failure}" \
    bash "$SCRIPT_PATH" repair
proof_record_step repair

assert_service_active xray
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy

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
    XRAY_FAILURE_PROOF_DIR="${E2E_PROOF_DIR:+${E2E_PROOF_DIR}/update-failure}"
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
proof_record_step update

assert_service_active xray
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy
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
    XRAY_FAILURE_PROOF_DIR="${E2E_PROOF_DIR:+${E2E_PROOF_DIR}/rollback-failure}" \
    bash "$SCRIPT_PATH" rollback "$backup_dir"
assert_service_active xray
proof_record_step rollback
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy

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
proof_record_step status
proof_capture_runtime_evidence

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
proof_record_step uninstall

echo "==> post-checks"
assert_path_absent /etc/xray
assert_path_absent /etc/xray-reality
assert_path_absent /usr/local/bin/xray
assert_path_absent /usr/local/bin/xray-reality.sh

for port in "${ports_before_uninstall[@]}"; do
    assert_port_not_listening "$port"
done

assert_user_absent xray
proof_record_step post-checks
proof_write_lifecycle_manifest

trap - EXIT
echo "e2e nightly smoke lifecycle check passed."
