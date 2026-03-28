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
    [[ "$output" == *"ok"* ]]
}

@test "auto-update template escapes XRAY_SCRIPT_PATH in exec line" {
    run bash -eo pipefail -c '
    grep -q "printf '\''exec %q update --non-interactive" ./modules/install/bootstrap.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
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
    [[ "$output" == *"ok"* ]]
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

@test "save_environment persists custom XRAY_DATA_DIR bootstrap contract" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_ENV="$tmp/config.env"
    XRAY_DATA_DIR="$tmp/runtime-tree"
    XRAY_ALLOW_CUSTOM_DATA_DIR=true
    atomic_write() {
      local target="$1"
      cat > "$target"
    }
    save_environment
    grep -Fq "XRAY_DATA_DIR=\"$tmp/runtime-tree\"" "$XRAY_ENV"
    grep -Fq "XRAY_ALLOW_CUSTOM_DATA_DIR=\"true\"" "$XRAY_ENV"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_config_file accepts persisted XRAY_ALLOW_CUSTOM_DATA_DIR bootstrap flag" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp="$(mktemp)"
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
XRAY_DATA_DIR="/tmp/custom-runtime-tree"
XRAY_ALLOW_CUSTOM_DATA_DIR="true"
EOF
    load_config_file "$tmp"
    [[ "$XRAY_DATA_DIR" == "/tmp/custom-runtime-tree" ]]
    [[ "$XRAY_ALLOW_CUSTOM_DATA_DIR" == "true" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "save_environment persists custom geo asset URLs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_ENV="$tmp/config.env"
    XRAY_GEOIP_URL="https://github.com/custom/geoip.dat"
    XRAY_GEOSITE_URL="https://github.com/custom/geosite.dat"
    XRAY_GEOIP_SHA256_URL="https://github.com/custom/geoip.dat.sha256sum"
    XRAY_GEOSITE_SHA256_URL="https://github.com/custom/geosite.dat.sha256sum"
    atomic_write() {
      local target="$1"
      cat > "$target"
    }
    save_environment
    grep -Fq '\''XRAY_GEOIP_URL="https://github.com/custom/geoip.dat"'\'' "$XRAY_ENV"
    grep -Fq '\''XRAY_GEOSITE_URL="https://github.com/custom/geosite.dat"'\'' "$XRAY_ENV"
    grep -Fq '\''XRAY_GEOIP_SHA256_URL="https://github.com/custom/geoip.dat.sha256sum"'\'' "$XRAY_ENV"
    grep -Fq '\''XRAY_GEOSITE_SHA256_URL="https://github.com/custom/geosite.dat.sha256sum"'\'' "$XRAY_ENV"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "policy round-trip preserves custom geo asset contract" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp="$(mktemp)"
    trap "rm -f \"$tmp\"" EXIT
    DOWNLOAD_HOST_ALLOWLIST="github.com,release-assets.githubusercontent.com"
    GEO_VERIFY_HASH=false
    GEO_VERIFY_STRICT=true
    XRAY_GEOIP_URL="https://github.com/custom/geoip.dat"
    XRAY_GEOSITE_URL="https://github.com/custom/geosite.dat"
    XRAY_GEOIP_SHA256_URL="https://github.com/custom/geoip.dat.sha256sum"
    XRAY_GEOSITE_SHA256_URL="https://github.com/custom/geosite.dat.sha256sum"
    backup_file() { :; }
    save_policy_file "$tmp"
    DOWNLOAD_HOST_ALLOWLIST=""
    GEO_VERIFY_HASH=true
    GEO_VERIFY_STRICT=false
    XRAY_GEOIP_URL=""
    XRAY_GEOSITE_URL=""
    XRAY_GEOIP_SHA256_URL=""
    XRAY_GEOSITE_SHA256_URL=""
    load_policy_file "$tmp"
    [[ "$DOWNLOAD_HOST_ALLOWLIST" == "github.com,release-assets.githubusercontent.com" ]]
    [[ "$GEO_VERIFY_HASH" == "false" ]]
    [[ "$GEO_VERIFY_STRICT" == "true" ]]
    [[ "$XRAY_GEOIP_URL" == "https://github.com/custom/geoip.dat" ]]
    [[ "$XRAY_GEOSITE_URL" == "https://github.com/custom/geosite.dat" ]]
    [[ "$XRAY_GEOIP_SHA256_URL" == "https://github.com/custom/geoip.dat.sha256sum" ]]
    [[ "$XRAY_GEOSITE_SHA256_URL" == "https://github.com/custom/geosite.dat.sha256sum" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "managed geo directories follow active geo contract only" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_BIN="/opt/xray-custom/bin/xray"
    XRAY_GEO_DIR=""
    mapfile -t dirs < <(managed_geo_directories)
    [[ "${#dirs[@]}" -eq 1 ]]
    [[ "${dirs[0]}" == "/opt/xray-custom/bin" ]]
    [[ "${dirs[0]}" != "/usr/local/share/xray" ]]
    XRAY_GEO_DIR="/srv/xray-assets"
    mapfile -t dirs < <(managed_geo_directories)
    [[ "${#dirs[@]}" -eq 1 ]]
    [[ "${dirs[0]}" == "/srv/xray-assets" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "wrapper completeness guard tracks current health runtime modules" {
    run bash -eo pipefail -c '
    grep -Fq '\''lib.sh'\'' ./xray-reality.sh
    grep -Fq '\''modules/health/self_check.sh'\'' ./xray-reality.sh
    grep -Fq '\''modules/health/measurements.sh'\'' ./xray-reality.sh
    grep -Fq '\''modules/health/operator_decision.sh'\'' ./xray-reality.sh
    grep -Fq '\''modules/health/doctor.sh'\'' ./xray-reality.sh
    grep -Fq '\''modules/health/measurements_aggregate.jq'\'' ./xray-reality.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "managed source tree root files include wrapper entrypoint" {
    run bash -eo pipefail -c '
    source ./lib.sh
    mapfile -t roots < <(managed_source_tree_root_files)
    [[ " ${roots[*]} " == *" xray-reality.sh "* ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
