#!/usr/bin/env bats

@test "measurement_ensure_storage does not chmod pre-existing custom parent dirs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    shared_parent="$tmp/existing-shared"
    mkdir -p "$shared_parent"
    chmod 0777 "$shared_parent"
    MEASUREMENTS_DIR="$tmp/measurements"
    MEASUREMENTS_SUMMARY_FILE="$shared_parent/latest-summary.json"
    MEASUREMENTS_ROTATION_STATE_FILE="$shared_parent/rotation-state.json"
    before=$(stat -c "%a" "$shared_parent")
    measurement_ensure_storage
    after=$(stat -c "%a" "$shared_parent")
    [[ "$before" == "$after" ]]
    [[ -d "$MEASUREMENTS_DIR" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self-check persistence does not chmod pre-existing custom parent dirs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    state_parent="$tmp/state"
    history_parent="$tmp/history"
    mkdir -p "$state_parent" "$history_parent"
    chmod 0777 "$state_parent" "$history_parent"
    SELF_CHECK_STATE_FILE="$state_parent/self-check.json"
    SELF_CHECK_HISTORY_FILE="$history_parent/self-check-history.ndjson"
    atomic_write() {
      local target="$1"
      cat > "$target"
    }
    state_before=$(stat -c "%a" "$state_parent")
    history_before=$(stat -c "%a" "$history_parent")
    self_check_write_state_json "{\"verdict\":\"ok\"}"
    self_check_append_history_json "{\"verdict\":\"ok\"}"
    state_after=$(stat -c "%a" "$state_parent")
    history_after=$(stat -c "%a" "$history_parent")
    [[ "$state_before" == "$state_after" ]]
    [[ "$history_before" == "$history_after" ]]
    test -f "$SELF_CHECK_STATE_FILE"
    test -f "$SELF_CHECK_HISTORY_FILE"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install_self_sync_tree mirrors wrapper entrypoint and removes stale files" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./modules/lib/lifecycle.sh
    source ./modules/install/bootstrap.sh
    log() { :; }
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    src="$tmp/src"
    dest="$tmp/dest"
    mkdir -p "$src/modules" "$src/data" "$src/scripts" "$dest"
    while IFS= read -r root_file; do
      printf "%s\n" "$root_file" > "$src/$root_file"
    done < <(install_self_source_tree_root_files)
    printf "stale\n" > "$dest/stale.txt"
    printf "old\n" > "$dest/xray-reality.sh"
    install_self_sync_tree "$src" "$dest"
    test -f "$dest/xray-reality.sh"
    grep -Fq "xray-reality.sh" "$dest/xray-reality.sh"
    ! test -e "$dest/stale.txt"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "directory backup snapshots restore XRAY_DATA_DIR after failed session" {
    run bash -eo pipefail -c '
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    tree="$tmp/xray-data"
    mkdir -p "$tree"
    printf "old\n" > "$tree/original.txt"
    (
      source ./lib.sh
      source ./modules/lib/lifecycle.sh
      log() { :; }
      XRAY_DATA_DIR="$tree"
      XRAY_BACKUP="$tmp/backups"
      backup_file "$XRAY_DATA_DIR"
      rm -rf "$XRAY_DATA_DIR"
      mkdir -p "$XRAY_DATA_DIR"
      printf "new\n" > "$XRAY_DATA_DIR/new.txt"
      exit 1
    ) || true
    test -f "$tree/original.txt"
    ! test -e "$tree/new.txt"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
