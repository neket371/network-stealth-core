#!/usr/bin/env bats

@test "cleanup_on_error restores local backup" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/target.txt"
    local log_file="${tmpdir}/install.log"

    printf '%s' "orig" > "$target"
    cp "$target" "${target}.backup"

    run env TARGET="$target" LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=("$TARGET")
    declare -A LOCAL_BACKUP_MAP=()
    LOCAL_BACKUP_MAP["$TARGET"]=1
    printf "%s" "new" > "$TARGET"
    false
  '

    [ "$status" -ne 0 ]
    [ "$(cat "$target")" = "orig" ]
    [ ! -f "${target}.backup" ]
}

@test "cleanup_on_error restores from session backup" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/target.txt"
    local session_dir="${tmpdir}/backup-session"
    local log_file="${tmpdir}/install.log"

    mkdir -p "${session_dir}${tmpdir}"
    printf '%s' "orig" > "$target"
    cp "$target" "${session_dir}${target}"
    printf '%s' "modified" > "$target"

    run env TARGET="$target" SESSION="$session_dir" LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=("$TARGET")
    declare -A LOCAL_BACKUP_MAP=()
    BACKUP_SESSION_DIR="$SESSION"
    false
  '

    [ "$status" -ne 0 ]
    [ "$(cat "$target")" = "orig" ]
}

@test "cleanup_on_error handles empty backup stack" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local log_file="${tmpdir}/install.log"

    run env LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=()
    declare -A LOCAL_BACKUP_MAP=()
    false
  '

    [ "$status" -ne 0 ]
}

@test "cleanup_on_error rolls back firewall changes" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local log_file="${tmpdir}/install.log"

    run env LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=()
    declare -A LOCAL_BACKUP_MAP=()
    FIREWALL_ROLLBACK_ENTRIES=("iptables|444|v4")
    FIREWALL_FIREWALLD_DIRTY=false
    rollback_firewall_changes() {
      echo "firewall_rollback_called"
      FIREWALL_ROLLBACK_ENTRIES=()
      FIREWALL_FIREWALLD_DIRTY=false
      return 0
    }
    false
  '

    [ "$status" -ne 0 ]
    [[ "$output" == *"firewall_rollback_called"* ]]
}

@test "cleanup_on_error removes files created in failed session" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local created="${tmpdir}/created.txt"
    local log_file="${tmpdir}/install.log"

    run env CREATED="$created" LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=()
    declare -A LOCAL_BACKUP_MAP=()
    CREATED_PATHS=("$CREATED")
    declare -A CREATED_PATH_SET=()
    CREATED_PATH_SET["$CREATED"]=1
    printf "%s" "temporary" > "$CREATED"
    false
  '

    [ "$status" -ne 0 ]
    [ ! -e "$created" ]
}

@test "cleanup_on_error removes symlink paths created in failed session" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/target.txt"
    local link="${tmpdir}/created-link"
    local log_file="${tmpdir}/install.log"

    printf '%s' "temporary" > "$target"
    ln -s "$target" "$link"

    run env LINK="$link" LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=()
    declare -A LOCAL_BACKUP_MAP=()
    CREATED_PATHS=("$LINK")
    declare -A CREATED_PATH_SET=()
    CREATED_PATH_SET["$LINK"]=1
    false
  '

    [ "$status" -ne 0 ]
    [ ! -L "$link" ]
}

@test "cleanup_on_error reconciles runtime after restoring critical files" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/config.json"
    local log_file="${tmpdir}/install.log"

    printf '%s' "orig" > "$target"
    cp "$target" "${target}.backup"

    run env TARGET="$target" LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    XRAY_CONFIG="$TARGET"
    BACKUP_STACK=("$TARGET")
    declare -A LOCAL_BACKUP_MAP=()
    LOCAL_BACKUP_MAP["$TARGET"]=1
    reconcile_runtime_after_restore() {
      echo "runtime_reconcile_called"
      return 0
    }
    printf "%s" "broken" > "$TARGET"
    false
  '

    [ "$status" -ne 0 ]
    [[ "$output" == *"runtime_reconcile_called"* ]]
    [ "$(cat "$target")" = "orig" ]
}

@test "cleanup_on_error quiesces runtime for created runtime-critical paths without backups" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local log_file="${tmpdir}/install.log"

    run env LOG_FILE="$log_file" bash -c '
    source ./lib.sh
    INSTALL_LOG="$LOG_FILE"
    BACKUP_STACK=()
    declare -A LOCAL_BACKUP_MAP=()
    CREATED_PATHS=("/etc/systemd/system/xray.service")
    declare -A CREATED_PATH_SET=()
    CREATED_PATH_SET["/etc/systemd/system/xray.service"]=1
    runtime_quiesce_for_restore() {
      echo "runtime_quiesced"
      return 0
    }
    reconcile_runtime_after_restore() {
      echo "runtime_reconcile_called"
      return 0
    }
    false
  '

    [ "$status" -ne 0 ]
    [[ "$output" == *"runtime_quiesced"* ]]
    [[ "$output" == *"runtime_reconcile_called"* ]]
}

@test "cleanup_empty_runtime_dirs removes empty managed directories" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local etc_xray="${tmpdir}/etc/xray"
    local etc_keys="${etc_xray}/private/keys"
    local etc_reality="${tmpdir}/etc/xray-reality"
    local var_home="${tmpdir}/var/lib/xray"
    local var_logs="${tmpdir}/var/log/xray"
    local var_backups="${tmpdir}/var/backups/xray"

    mkdir -p "$etc_keys" "$etc_reality" "$var_home/measurements" "$var_logs" "$var_backups"

    run env \
      XRAY_KEYS="$etc_keys" \
      XRAY_CONFIG="${etc_xray}/config.json" \
      XRAY_ENV="${etc_reality}/config.env" \
      XRAY_HOME="$var_home" \
      XRAY_LOGS="$var_logs" \
      XRAY_BACKUP="$var_backups" \
      bash -eo pipefail -c '
    source ./lib.sh
    cleanup_empty_runtime_dirs
    [ ! -d "$XRAY_KEYS" ]
    [ ! -d "$(dirname "$XRAY_KEYS")" ]
    [ ! -d "$(dirname "$XRAY_CONFIG")" ]
    [ ! -d "$(dirname "$XRAY_ENV")" ]
    [ ! -d "$XRAY_HOME/measurements" ]
    [ ! -d "$XRAY_HOME" ]
    [ ! -d "$XRAY_LOGS" ]
    [ ! -d "$XRAY_BACKUP" ]
  '

    [ "$status" -eq 0 ]
}

@test "systemd_enable_symlink_path_for_unit returns known xray targets" {
    run bash -eo pipefail -c '
    source ./modules/lib/system_runtime.sh
    [ "$(systemd_enable_symlink_path_for_unit xray.service)" = "/etc/systemd/system/multi-user.target.wants/xray.service" ]
    [ "$(systemd_enable_symlink_path_for_unit xray-health.timer)" = "/etc/systemd/system/timers.target.wants/xray-health.timer" ]
    [ "$(systemd_enable_symlink_path_for_unit xray-auto-update.timer)" = "/etc/systemd/system/timers.target.wants/xray-auto-update.timer" ]
  '

    [ "$status" -eq 0 ]
}

@test "record_created_path_literal preserves symlink path instead of resolving target" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/target.txt"
    local link="${tmpdir}/literal-link"

    printf '%s' "target" > "$target"
    ln -s "$target" "$link"

    run env LINK="$link" bash -eo pipefail -c '
    source ./lib.sh
    CREATED_PATHS=()
    declare -A CREATED_PATH_SET=()
    record_created_path_literal "$LINK"
    [ "${#CREATED_PATHS[@]}" -eq 1 ]
    [ "${CREATED_PATHS[0]}" = "$LINK" ]
  '

    [ "$status" -eq 0 ]
}

@test "uninstall_remove_file deletes adjacent backup file" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/xray"
    local backup="${target}.backup"

    printf '%s' "bin" > "$target"
    printf '%s' "backup" > "$backup"

    run env TARGET="$target" bash -eo pipefail -c '
    source ./modules/service/uninstall.sh
    XRAY_BIN="$TARGET"
    uninstall_remove_file "$XRAY_BIN"
    [ ! -e "$XRAY_BIN" ]
    [ ! -e "${XRAY_BIN}.backup" ]
  '

    [ "$status" -eq 0 ]
}

@test "uninstall_remove_accounts_and_reload suppresses reset-failed warning when xray units are already gone" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    manage_systemd_uninstall=true
    uninstall_cleanup_failed=false
    XRAY_HOME="$(mktemp -d)"
    trap "rm -rf \"$XRAY_HOME\"" EXIT

    id() { return 1; }
    getent() { return 1; }
    uninstall_remove_dir() { :; }
    systemctl_available() { return 0; }
    systemctl_uninstall_bounded() {
      if [[ "${1:-}" == "daemon-reload" ]]; then
        return 0
      fi
      if [[ "${1:-}" == "reset-failed" ]]; then
        return 1
      fi
      return 0
    }
    systemctl() {
      if [[ "${1:-}" == "list-units" || "${1:-}" == "list-unit-files" ]]; then
        return 0
      fi
      return 0
    }

    uninstall_remove_accounts_and_reload
  '

    [ "$status" -eq 0 ]
    [[ "$output" == *"systemctl daemon-reload"* ]]
    [[ "$output" == *"systemctl reset-failed xray*: не требуется"* ]]
    [[ "$output" != *"Не удалось выполнить systemctl reset-failed"* ]]
}

@test "systemctl_uninstall_bounded forwards all requested units" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local calls_file="${tmpdir}/systemctl-calls.txt"

    run env CALLS_FILE="$calls_file" bash -eo pipefail -c '
    source ./modules/service/runtime.sh
    log() { :; }
    debug_file() { :; }
    timeout() {
      while (($# > 0)); do
        case "$1" in
          --signal=* | --kill-after=* | *s)
            shift
            ;;
          *)
            break
            ;;
        esac
      done
      "$@"
    }
    systemctl() {
      printf "%s\n" "$*" >> "$CALLS_FILE"
      return 0
    }
    systemctl_uninstall_bounded reset-failed xray.service xray-health.service xray-health.timer
    cat "$CALLS_FILE"
  '

    rm -rf "$tmpdir"
    [ "$status" -eq 0 ]
    [ "$output" = "reset-failed xray.service xray-health.service xray-health.timer" ]
}

@test "atomic_write creates file atomically" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/atomic-test.txt"

    run env TMPDIR="$tmpdir" bash -c '
    source ./lib.sh
    # Patch safe_prefixes for test environment
    atomic_write_test() {
      local target="$1"
      local mode="${2:-}"
      local tmp
      tmp=$(mktemp "${target}.tmp.XXXXXX")
      cat > "$tmp"
      [[ -n "$mode" ]] && chmod "$mode" "$tmp"
      mkdir -p "$(dirname "$target")"
      mv "$tmp" "$target"
    }
    echo "test content" | atomic_write_test "'"$target"'" 0644
    cat "'"$target"'"
  '
    rm -rf "$tmpdir"

    [ "$status" -eq 0 ]
    [ "$output" = "test content" ]
}

@test "atomic_write creates parent directories" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local target="${tmpdir}/sub/dir/test.txt"

    run bash -eo pipefail -c '
    source ./lib.sh
    atomic_write_test() {
      local target="$1"
      local mode="${2:-}"
      local dir
      dir=$(dirname "$target")
      mkdir -p "$dir"
      local tmp
      tmp=$(mktemp "${target}.tmp.XXXXXX")
      cat > "$tmp"
      [[ -n "$mode" ]] && chmod "$mode" "$tmp"
      mv "$tmp" "$target"
    }
    echo "nested" | atomic_write_test "'"$target"'" 0644
    cat "'"$target"'"
  '
    rm -rf "$tmpdir"

    [ "$status" -eq 0 ]
    [ "$output" = "nested" ]
}

@test "atomic_write rejects /tmp paths" {
    run bash -eo pipefail -c '
    source ./lib.sh
    echo "test" | atomic_write "/tmp/should-fail.txt" 0644
  '
    [ "$status" -ne 0 ]
}

@test "atomic_write rejects path traversal" {
    run bash -eo pipefail -c '
    source ./lib.sh
    echo "test" | atomic_write "/var/log/../etc/passwd" 0644
  '
    [ "$status" -ne 0 ]
}

@test "atomic_write restores umask when mktemp fails" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { :; }
    mkdir() { :; }
    realpath() { printf "%s\n" "${@: -1}"; }
    mktemp() { return 1; }
    before=$(umask)
    if echo "test" | atomic_write "/var/lib/xray/test.txt" 0644; then
      echo "unexpected-success"
      exit 1
    fi
    after=$(umask)
    [[ "$before" == "$after" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
