#!/usr/bin/env bats

@test "path safety requires exact project scope segments for destructive system paths" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_KEYS="/etc/xray/private/keys"
    XRAY_BACKUP="/var/backups/xray"
    XRAY_LOGS="/var/log/xray"
    XRAY_HOME="/var/lib/xray-evil"
    XRAY_DATA_DIR="/usr/local/share/xray-reality"
    XRAY_GEO_DIR="/usr/local/share/xray"
    XRAY_BIN="/usr/local/bin/xray"
    XRAY_CONFIG="/etc/xray/config.json"
    XRAY_ENV="/etc/xray-reality/config.env"
    XRAY_SCRIPT_PATH="/usr/local/bin/xray-reality.sh"
    XRAY_UPDATE_SCRIPT="/usr/local/bin/xray-reality-update.sh"
    MINISIGN_KEY="/etc/xray/minisign.pub"
    if strict_validate_runtime_inputs uninstall; then
      echo "unexpected-pass"
      exit 1
    fi
  '
    [ "$status" -eq 0 ]
    [[ "$output" != *"unexpected-pass"* ]]
}

@test "uninstall_has_managed_artifacts detects residue-only managed logs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./modules/service/uninstall.sh
    tmpdir="$(mktemp -d)"
    trap "rm -rf \"$tmpdir\"" EXIT
    XRAY_LOGS="$tmpdir/logs"
    HEALTH_LOG="$tmpdir/logs/xray-health.log"
    mkdir -p "$XRAY_LOGS"
    : > "$HEALTH_LOG"
    uninstall_has_managed_artifacts
    echo "present"
  '
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "present" ]
}

@test "install_self_sync_tree stages root files atomically while preserving existing extras" {
    run bash -eo pipefail -c '
    source ./modules/install/bootstrap.sh
    log() { :; }

    src_root="$(mktemp -d)"
    dest_root="$(mktemp -d)"
    trap "rm -rf \"$src_root\" \"$dest_root\"" EXIT

    mkdir -p "$src_root/modules/lib" "$src_root/data/domains" "$src_root/scripts/lab"
    printf "%s\n" "new-lib" > "$src_root/lib.sh"
    printf "%s\n" "module" > "$src_root/modules/lib/sample.sh"
    printf "%s\n" "catalog" > "$src_root/data/domains/catalog.json"
    printf "%s\n" "script" > "$src_root/scripts/lab/sample.sh"

    printf "%s\n" "old-lib" > "$dest_root/lib.sh"
    printf "%s\n" "keep-me" > "$dest_root/custom-extra.txt"

    install_self_sync_tree "$src_root" "$dest_root"

    [[ "$(cat "$dest_root/lib.sh")" == "new-lib" ]]
    [[ "$(cat "$dest_root/modules/lib/sample.sh")" == "module" ]]
    [[ "$(cat "$dest_root/data/domains/catalog.json")" == "catalog" ]]
    [[ "$(cat "$dest_root/scripts/lab/sample.sh")" == "script" ]]
    [[ "$(cat "$dest_root/custom-extra.txt")" == "keep-me" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
