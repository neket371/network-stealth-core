#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"

START_PORT="${START_PORT:-24040}"
INITIAL_CONFIGS="${INITIAL_CONFIGS:-2}"
ADD_CONFIGS="${ADD_CONFIGS:-1}"

cleanup() {
    cleanup_installation "$SCRIPT_PATH"
}

trap cleanup EXIT

echo "==> pre-clean"
cleanup

echo "==> install"
run_root env \
    NON_INTERACTIVE=true \
    ASSUME_YES=true \
    XRAY_NUM_CONFIGS="$INITIAL_CONFIGS" \
    START_PORT="$START_PORT" \
    SERVER_IP=127.0.0.1 \
    DOMAIN_CHECK=false \
    SKIP_REALITY_CHECK=true \
    ALLOW_INSECURE_SHA256=true \
    bash "$SCRIPT_PATH" install
assert_service_active xray
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy
force_rotate_xray_logs_and_assert_healthy

echo "==> status"
run_root bash "$SCRIPT_PATH" status --verbose | run_root tee /tmp/xru-status-before.txt > /dev/null
grep -q "Inbounds:" /tmp/xru-status-before.txt

before_count="$(run_root jq '.inbounds | length' /etc/xray/config.json)"
if ((before_count < INITIAL_CONFIGS)); then
    echo "Expected at least ${INITIAL_CONFIGS} inbounds, got ${before_count}" >&2
    exit 1
fi

for path in /etc/xray/config.json /etc/xray/private/keys/keys.txt /etc/xray/private/keys/clients.txt /etc/xray/private/keys/clients.json; do
    run_root test -f "$path"
done

echo "==> add-clients"
run_root env NON_INTERACTIVE=true ASSUME_YES=true bash "$SCRIPT_PATH" add-clients "$ADD_CONFIGS"
assert_service_active xray
assert_xray_runtime_logs_contract
restart_xray_and_assert_healthy

after_count="$(run_root jq '.inbounds | length' /etc/xray/config.json)"
expected_after=$((before_count + ADD_CONFIGS))
if ((after_count != expected_after)); then
    echo "Expected ${expected_after} inbounds after add-clients, got ${after_count}" >&2
    exit 1
fi

mapfile -t ports_before_uninstall < <(collect_ports_from_config /etc/xray/config.json)
if [[ ${#ports_before_uninstall[@]} -eq 0 ]]; then
    echo "No ports detected in /etc/xray/config.json" >&2
    exit 1
fi

echo "==> uninstall"
run_root bash "$SCRIPT_PATH" uninstall --yes --non-interactive

echo "==> post-checks"
for path in \
    /etc/xray \
    /etc/xray-reality \
    /usr/local/bin/xray \
    /usr/local/bin/xray-reality.sh; do
    assert_path_absent "$path"
done

for port in "${ports_before_uninstall[@]}"; do
    assert_port_not_listening "$port"
done

assert_user_absent xray

trap - EXIT
echo "E2E lifecycle check passed."
