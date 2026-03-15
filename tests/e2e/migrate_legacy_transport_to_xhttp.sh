#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"

START_PORT="${START_PORT:-24640}"
INITIAL_CONFIGS="${INITIAL_CONFIGS:-2}"
CLIENTS_JSON="/etc/xray/private/keys/clients.json"
STATUS_BEFORE="/tmp/xru-migrate-before.txt"
STATUS_AFTER="/tmp/xru-migrate-after.txt"
STATUS_REPAIR="/tmp/xru-migrate-repair.txt"
LEGACY_BOOTSTRAP="/tmp/xru-legacy-bootstrap.sh"
LEGACY_LOGS="${LEGACY_LOGS:-/var/lib/xray/legacy-logs}"

cleanup() {
    cleanup_installation "$SCRIPT_PATH"
    rm -f "$STATUS_BEFORE" "$STATUS_AFTER" "$STATUS_REPAIR" "$LEGACY_BOOTSTRAP"
}

trap cleanup EXIT

echo "==> pre-clean"
cleanup

echo "==> prepare legacy bootstrap wrapper"
cp "$ROOT_DIR/xray-reality.sh" "$LEGACY_BOOTSTRAP"
chmod +x "$LEGACY_BOOTSTRAP"

echo "==> install legacy grpc profile from v5.1.0"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    XRAY_NUM_CONFIGS="$INITIAL_CONFIGS" \
    XRAY_TRANSPORT=grpc \
    XRAY_REPO_REF=v5.1.0 \
    XRAY_LOGS="$LEGACY_LOGS" \
    START_PORT="$START_PORT" \
    SERVER_IP=127.0.0.1 \
    DOMAIN_CHECK=false \
    SKIP_REALITY_CHECK=true \
    ALLOW_INSECURE_SHA256=true \
    bash "$LEGACY_BOOTSTRAP" install
assert_service_active xray

run_root bash "$SCRIPT_PATH" status --verbose > "$STATUS_BEFORE"
grep -q "Transport: grpc" "$STATUS_BEFORE"
grep -q "legacy transport" "$STATUS_BEFORE"

# shellcheck disable=SC2016
transport_before="$(run_root awk -F'"' '/^TRANSPORT=/{print $2; exit}' /etc/xray-reality/config.env || true)"
if [[ "$transport_before" != "grpc" ]]; then
    echo "expected TRANSPORT=grpc before migration, got: ${transport_before}" >&2
    exit 1
fi

assert_clients_json_legacy_contract "$CLIENTS_JSON" "$INITIAL_CONFIGS" "grpc"

if run_root find /etc/xray/private/keys/export/raw-xray -maxdepth 1 -type f -name 'config-*.json' 2> /dev/null | grep -q .; then
    echo "legacy grpc install unexpectedly generated raw xray xhttp exports" >&2
    exit 1
fi

echo "==> migrate legacy transport to xhttp"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256=true \
    bash "$SCRIPT_PATH" migrate-stealth
assert_service_active xray

run_root bash "$SCRIPT_PATH" status --verbose > "$STATUS_AFTER"
grep -q "Transport: xhttp" "$STATUS_AFTER"
if grep -q "legacy transport" "$STATUS_AFTER"; then
    echo "legacy transport warning still present after migration" >&2
    exit 1
fi

# shellcheck disable=SC2016
transport_after="$(run_root awk -F'"' '/^TRANSPORT=/{print $2; exit}' /etc/xray-reality/config.env || true)"
# shellcheck disable=SC2016
mux_after="$(run_root awk -F'"' '/^MUX_MODE=/{print $2; exit}' /etc/xray-reality/config.env || true)"
if [[ "$transport_after" != "xhttp" ]]; then
    echo "expected TRANSPORT=xhttp after migration, got: ${transport_after}" >&2
    exit 1
fi
if [[ "$mux_after" != "off" ]]; then
    echo "expected MUX_MODE=off after migration, got: ${mux_after}" >&2
    exit 1
fi

assert_clients_json_xhttp_contract "$CLIENTS_JSON" "$INITIAL_CONFIGS"
assert_raw_xray_exports_exist "$CLIENTS_JSON"
run_root test -f /etc/xray-reality/policy.json
run_root test -f /etc/xray/private/keys/export/canary/manifest.json

echo "==> repair migrated xhttp install"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    ALLOW_INSECURE_SHA256=true \
    bash "$SCRIPT_PATH" repair
assert_service_active xray

run_root bash "$SCRIPT_PATH" status --verbose > "$STATUS_REPAIR"
grep -q "Transport: xhttp" "$STATUS_REPAIR"

mapfile -t ports_before_uninstall < <(collect_ports_from_config /etc/xray/config.json)
if [[ ${#ports_before_uninstall[@]} -eq 0 ]]; then
    echo "no ports detected before uninstall after migration" >&2
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
echo "legacy transport migration check passed."
