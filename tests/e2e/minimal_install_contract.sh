#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"

START_PORT="${START_PORT:-24340}"
EXPECTED_CONFIGS="${EXPECTED_CONFIGS:-5}"
CLIENTS_JSON="/etc/xray/private/keys/clients.json"
CLIENTS_TXT="/etc/xray/private/keys/clients.txt"
STATUS_FILE="/tmp/xru-minimal-status.txt"

cleanup() {
    cleanup_installation "$SCRIPT_PATH"
    rm -f "$STATUS_FILE"
}

trap cleanup EXIT

echo "==> pre-clean"
cleanup

echo "==> interactive minimal install"
export ROOT_DIR SCRIPT_PATH START_PORT
expect << 'EXPECT_INSTALL'
set timeout 900

spawn bash -lc "source \"$env(ROOT_DIR)/tests/e2e/lib.sh\"; run_root env START_PORT=$env(START_PORT) SERVER_IP=127.0.0.1 DOMAIN_CHECK=false SKIP_REALITY_CHECK=true ALLOW_INSECURE_SHA256=true bash \"$env(SCRIPT_PATH)\" install"

expect {
    -re {Профиль \[1/2/3/4\]:} {
        puts stderr "unexpected advanced profile prompt during minimal install"
        exit 1
    }
    -re {(Сколько VPN-ключей создать\?|Количество VPN-ключей|Количество конфигов) \(1-[0-9]+\):} {
        puts stderr "unexpected manual count prompt during minimal install"
        exit 1
    }
    timeout {
        puts stderr "timed out during minimal install"
        exit 1
    }
    eof {}
}

set rc [wait]
set code [lindex $rc 3]
if {$code != 0} {
    exit $code
}
EXPECT_INSTALL

assert_service_active xray

# shellcheck disable=SC2016
tier_value="$(run_root awk -F'"' '/^DOMAIN_TIER=/{print $2; exit}' /etc/xray-reality/config.env || true)"
# shellcheck disable=SC2016
transport_value="$(run_root awk -F'"' '/^TRANSPORT=/{print $2; exit}' /etc/xray-reality/config.env || true)"
# shellcheck disable=SC2016
mux_value="$(run_root awk -F'"' '/^MUX_MODE=/{print $2; exit}' /etc/xray-reality/config.env || true)"
# shellcheck disable=SC2016
advanced_value="$(run_root awk -F'"' '/^ADVANCED_MODE=/{print $2; exit}' /etc/xray-reality/config.env || true)"

if [[ "$tier_value" != "tier_ru" ]]; then
    echo "expected DOMAIN_TIER=tier_ru after minimal install, got: ${tier_value}" >&2
    exit 1
fi
if [[ "$transport_value" != "xhttp" ]]; then
    echo "expected TRANSPORT=xhttp after minimal install, got: ${transport_value}" >&2
    exit 1
fi
if [[ "$mux_value" != "off" ]]; then
    echo "expected MUX_MODE=off after minimal install, got: ${mux_value}" >&2
    exit 1
fi
if [[ "$advanced_value" != "false" ]]; then
    echo "expected ADVANCED_MODE=false after minimal install, got: ${advanced_value}" >&2
    exit 1
fi

run_root bash "$SCRIPT_PATH" status --verbose > "$STATUS_FILE"
grep -q "Transport: xhttp" "$STATUS_FILE"
grep -q "Inbounds:" "$STATUS_FILE"

assert_clients_json_xhttp_contract "$CLIENTS_JSON" "$EXPECTED_CONFIGS"
assert_raw_xray_exports_exist "$CLIENTS_JSON"
run_root grep -q "вариант: запасная (rescue)" "$CLIENTS_TXT"
run_root grep -q "режим: packet-up" "$CLIENTS_TXT"
run_root grep -q "вариант: аварийная (emergency)" "$CLIENTS_TXT"
run_root grep -q "режим: stream-up" "$CLIENTS_TXT"
run_root grep -q "browser dialer" "$CLIENTS_TXT"
run_root test -f /etc/xray-reality/policy.json
run_root test -f /etc/xray/private/keys/export/raw-xray-index.json
run_root test -f /etc/xray/private/keys/export/v2rayn-links.json
run_root test -f /etc/xray/private/keys/export/nekoray-template.json
run_root test -f /etc/xray/private/keys/export/canary/manifest.json
run_root test -f /etc/xray/private/keys/export/canary/measure-linux.sh
run_root test -f /etc/xray/private/keys/export/canary/measure-windows.ps1
run_root test -f /etc/xray/private/keys/export/compatibility-notes.txt

config_count="$(run_root jq '[.inbounds[] | select(.listen == "0.0.0.0" or .listen == null)] | length' /etc/xray/config.json)"
if ((config_count != EXPECTED_CONFIGS)); then
    echo "expected ${EXPECTED_CONFIGS} ipv4 inbounds after minimal install, got ${config_count}" >&2
    exit 1
fi

mapfile -t ports_before_uninstall < <(collect_ports_from_config /etc/xray/config.json)
if [[ ${#ports_before_uninstall[@]} -eq 0 ]]; then
    echo "no ports detected in /etc/xray/config.json" >&2
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
echo "minimal install contract check passed."
