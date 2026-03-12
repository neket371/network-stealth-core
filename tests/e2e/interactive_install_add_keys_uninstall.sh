#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"

START_PORT="${START_PORT:-24120}"
INITIAL_CONFIGS="${INITIAL_CONFIGS:-3}"
ADD_CONFIGS="${ADD_CONFIGS:-2}"

cleanup() {
    cleanup_installation "$SCRIPT_PATH"
}

trap cleanup EXIT

echo "==> pre-clean"
cleanup

echo "==> interactive advanced install (global-50 profile)"
export ROOT_DIR SCRIPT_PATH START_PORT INITIAL_CONFIGS ADD_CONFIGS
expect << 'EXPECT_INSTALL'
set timeout 900
set saw_profile 0
set saw_count 0

spawn bash -lc "source \"$env(ROOT_DIR)/tests/e2e/lib.sh\"; run_root env START_PORT=$env(START_PORT) SERVER_IP=127.0.0.1 DOMAIN_CHECK=false SKIP_REALITY_CHECK=true ALLOW_INSECURE_SHA256=true bash \"$env(SCRIPT_PATH)\" install --advanced"

expect {
    -re {Профиль \[1/2/3/4\]:} {
        send -- "2\r"
        set saw_profile 1
        exp_continue
    }
    -re {(Сколько VPN-ключей создать\?|Количество VPN-ключей|Количество конфигов) \(1-15\):} {
        send -- "$env(INITIAL_CONFIGS)\r"
        set saw_count 1
        exp_continue
    }
    timeout {
        puts stderr "Timed out during interactive install"
        exit 1
    }
    eof {}
}

set rc [wait]
set code [lindex $rc 3]
if {$code != 0} {
    exit $code
}
if {$saw_profile != 1 || $saw_count != 1} {
    puts stderr "Advanced install prompts were not observed"
    exit 1
}
EXPECT_INSTALL

tier_value="$(run_root awk -F'"' "/^DOMAIN_TIER=/{print \$2; exit}" /etc/xray-reality/config.env || true)"
if [[ "$tier_value" != "tier_global_ms10" ]]; then
    echo "Expected DOMAIN_TIER=tier_global_ms10 after interactive install, got: ${tier_value}" >&2
    exit 1
fi

count_before="$(run_root jq '[.inbounds[] | select(.listen == "0.0.0.0" or .listen == null)] | length' /etc/xray/config.json)"
if ((count_before != INITIAL_CONFIGS)); then
    echo "Expected ${INITIAL_CONFIGS} IPv4 inbounds after install, got ${count_before}" >&2
    exit 1
fi

echo "==> interactive add-keys"
expect << 'EXPECT_ADD_KEYS'
set timeout 900
set saw_prompt 0

spawn bash -lc "source \"$env(ROOT_DIR)/tests/e2e/lib.sh\"; run_root bash \"$env(SCRIPT_PATH)\" add-keys"

expect {
    -re {(Сколько VPN-ключей добавить\?|Количество VPN-ключей( добавить)?|Количество конфигов добавить) \(1-[0-9]+\):} {
        send -- "$env(ADD_CONFIGS)\r"
        set saw_prompt 1
        exp_continue
    }
    timeout {
        puts stderr "Timed out during interactive add-keys"
        exit 1
    }
    eof {}
}

set rc [wait]
set code [lindex $rc 3]
if {$code != 0} {
    exit $code
}
if {$saw_prompt != 1} {
    puts stderr "Interactive add-keys prompt was not observed"
    exit 1
}
EXPECT_ADD_KEYS

count_after="$(run_root jq '[.inbounds[] | select(.listen == "0.0.0.0" or .listen == null)] | length' /etc/xray/config.json)"
expected_after=$((count_before + ADD_CONFIGS))
if ((count_after != expected_after)); then
    echo "Expected ${expected_after} IPv4 inbounds after add-keys, got ${count_after}" >&2
    exit 1
fi
if ((count_after > 15)); then
    echo "global-50 limit violated: got ${count_after} inbounds" >&2
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
assert_path_absent /etc/xray
assert_path_absent /etc/xray-reality
assert_path_absent /usr/local/bin/xray
assert_path_absent /usr/local/bin/xray-reality.sh

for port in "${ports_before_uninstall[@]}"; do
    assert_port_not_listening "$port"
done

assert_user_absent xray

trap - EXIT
echo "E2E interactive lifecycle check passed."
