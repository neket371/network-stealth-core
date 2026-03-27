#!/usr/bin/env bats

@test "auto-update template delegates geo refresh to shared update path" {
    run bash -eo pipefail -c '
    grep -Fq "printf '\''exec %q update --non-interactive" ./modules/install/bootstrap.sh
    ! grep -Fq '\''download_geo_with_verify'\'' ./modules/install/bootstrap.sh
    ! grep -Fq '\''GEOIP_URL='\'' ./modules/install/bootstrap.sh
    ! grep -Fq '\''GEO_VERIFY_STRICT='\'' ./modules/install/bootstrap.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "auto-update template escapes XRAY_SCRIPT_PATH in exec line" {
    run bash -eo pipefail -c '
    grep -q "printf '\''exec %q update --non-interactive" ./modules/install/bootstrap.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "auto-update template emits shell shebang for systemd ExecStart" {
    run bash -eo pipefail -c '
    grep -Fq "#!/usr/bin/env bash" ./modules/install/bootstrap.sh
    grep -Fq "set -euo pipefail" ./modules/install/bootstrap.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_config_file accepts MEASUREMENTS_ROTATION_STATE_FILE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp="$(mktemp)"
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
MEASUREMENTS_SUMMARY_FILE="/tmp/custom/latest-summary.json"
MEASUREMENTS_ROTATION_STATE_FILE="/tmp/custom/rotation-state.json"
EOF
    load_config_file "$tmp"
    [[ "$MEASUREMENTS_SUMMARY_FILE" == "/tmp/custom/latest-summary.json" ]]
    [[ "$MEASUREMENTS_ROTATION_STATE_FILE" == "/tmp/custom/rotation-state.json" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "sync_measurements_rotation_state_file_contract follows summary path changes unless explicitly overridden" {
    run bash -eo pipefail -c '
    source ./lib.sh
    MEASUREMENTS_SUMMARY_FILE="/var/lib/xray/measurements/latest-summary.json"
    MEASUREMENTS_ROTATION_STATE_FILE="/var/lib/xray/measurements/rotation-state.json"
    previous_summary="$MEASUREMENTS_SUMMARY_FILE"
    MEASUREMENTS_SUMMARY_FILE="/tmp/lab/latest-summary.json"
    sync_measurements_rotation_state_file_contract "$previous_summary"
    [[ "$MEASUREMENTS_ROTATION_STATE_FILE" == "/tmp/lab/rotation-state.json" ]]
    MEASUREMENTS_ROTATION_STATE_FILE="/tmp/custom/rotation-state.json"
    previous_summary="$MEASUREMENTS_SUMMARY_FILE"
    MEASUREMENTS_SUMMARY_FILE="/tmp/other/latest-summary.json"
    sync_measurements_rotation_state_file_contract "$previous_summary"
    [[ "$MEASUREMENTS_ROTATION_STATE_FILE" == "/tmp/custom/rotation-state.json" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "save_environment persists MEASUREMENTS_ROTATION_STATE_FILE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_ENV="$tmp/config.env"
    MEASUREMENTS_DIR="$tmp/measurements"
    MEASUREMENTS_SUMMARY_FILE="$tmp/measurements/latest-summary.json"
    MEASUREMENTS_ROTATION_STATE_FILE="$tmp/measurements/rotation-state.json"
    mkdir -p "$tmp"
    atomic_write() {
      local target="$1"
      cat > "$target"
    }
    save_environment
    grep -Fq '\''MEASUREMENTS_ROTATION_STATE_FILE="'\'' "$XRAY_ENV"
    grep -Fq '\''rotation-state.json"'\'' "$XRAY_ENV"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
