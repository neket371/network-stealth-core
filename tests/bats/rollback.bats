#!/usr/bin/env bats

@test "rollback_from_session fails when session directory does not exist" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    XRAY_BACKUP="$(mktemp -d)"
    rollback_from_session "$XRAY_BACKUP/not-found"
  '
    [ "$status" -ne 0 ]
}

@test "rollback_from_session rejects backup outside XRAY_BACKUP root" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    XRAY_BACKUP="$(mktemp -d)"
    outside="$(mktemp -d)"
    rollback_from_session "$outside"
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"вне разрешённой директории"* ]]
}

@test "rollback_from_session restores custom runtime path from session backup" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    XRAY_BACKUP="$(mktemp -d)"
    custom_root="$(mktemp -d)"
    XRAY_CONFIG="${custom_root}/etc/xray/config.json"
    XRAY_ENV="${custom_root}/etc/xray-reality/config.env"
    XRAY_KEYS="${custom_root}/etc/xray/private/keys"
    XRAY_LOGS="${custom_root}/var/log/xray"
    XRAY_HOME="${custom_root}/var/lib/xray"
    XRAY_DATA_DIR="${custom_root}/usr/local/share/xray-reality"
    XRAY_BIN="${custom_root}/usr/local/bin/xray"
    XRAY_SCRIPT_PATH="${custom_root}/usr/local/bin/xray-reality.sh"
    XRAY_UPDATE_SCRIPT="${custom_root}/usr/local/bin/xray-reality-update.sh"
    MINISIGN_KEY="${custom_root}/etc/xray/minisign.pub"

    session_dir="${XRAY_BACKUP}/session-ok"
    mkdir -p "${session_dir}$(dirname "$XRAY_CONFIG")"
    printf "restored-config" > "${session_dir}${XRAY_CONFIG}"
    rm -f "$XRAY_CONFIG"

    systemd_running() { return 1; }
    rollback_from_session "$session_dir"
    cat "$XRAY_CONFIG"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"restored-config"* ]]
}

@test "rollback_from_session logs restore target before failing" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    XRAY_BACKUP="$(mktemp -d)"
    custom_root="$(mktemp -d)"
    XRAY_CONFIG="${custom_root}/etc/xray/config.json"
    XRAY_ENV="${custom_root}/etc/xray-reality/config.env"
    XRAY_KEYS="${custom_root}/etc/xray/private/keys"
    XRAY_LOGS="${custom_root}/var/log/xray"
    XRAY_HOME="${custom_root}/var/lib/xray"
    XRAY_DATA_DIR="${custom_root}/usr/local/share/xray-reality"
    XRAY_BIN="${custom_root}/usr/local/bin/xray"
    XRAY_SCRIPT_PATH="${custom_root}/usr/local/bin/xray-reality.sh"
    XRAY_UPDATE_SCRIPT="${custom_root}/usr/local/bin/xray-reality-update.sh"
    MINISIGN_KEY="${custom_root}/etc/xray/minisign.pub"

    session_dir="${XRAY_BACKUP}/session-fail"
    mkdir -p "${session_dir}$(dirname "$XRAY_CONFIG")"
    printf "broken" > "${session_dir}${XRAY_CONFIG}"

    log() { printf "%s\n" "$*"; }
    systemd_running() { return 1; }
    restore_file_from_snapshot() { return 1; }

    rollback_from_session "$session_dir"
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Не удалось восстановить: "* ]]
}
