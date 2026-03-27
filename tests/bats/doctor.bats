#!/usr/bin/env bats

@test "doctor shows install guidance when managed install is absent" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_BIN="$tmp_dir/missing-xray"
    XRAY_ENV="$tmp_dir/missing-config.env"
    XRAY_CONFIG="$tmp_dir/missing-config.json"

    doctor_flow
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT INSTALLED"* ]]
    [[ "$output" == *"sudo xray-reality.sh install"* ]]
}

@test "doctor recommends repair on broken self-check" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_ENV="$tmp_dir/config.env"
    printf "#!/usr/bin/env bash\necho Xray 25.9.5\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    printf "{}\n" > "$XRAY_CONFIG"
    printf "TRANSPORT=xhttp\n" > "$XRAY_ENV"

    managed_install_contract_present() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() {
      if [[ "${1:-}" == "is-active" ]]; then
        printf "active\n"
        return 0
      fi
      return 0
    }
    xray_config_test_ok() { return 0; }
    xray_installed_version() { printf "25.9.5\n"; }
    self_check_status_summary_tsv() {
      printf "BROKEN\trepair\t2026-03-26T00:00:00Z\tcfg-1\trecommended\tauto\tipv4\t15\n"
    }

    doctor_flow
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"BROKEN"* ]]
    [[ "$output" == *"sudo xray-reality.sh repair --non-interactive --yes"* ]]
}

@test "doctor recommends update --replan when field summary wants spare promotion" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_BIN="$tmp_dir/xray"
    XRAY_CONFIG="$tmp_dir/config.json"
    XRAY_ENV="$tmp_dir/config.env"
    printf "#!/usr/bin/env bash\necho Xray 25.9.5\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    printf "{}\n" > "$XRAY_CONFIG"
    printf "TRANSPORT=xhttp\n" > "$XRAY_ENV"

    managed_install_contract_present() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() {
      if [[ "${1:-}" == "is-active" ]]; then
        printf "active\n"
        return 0
      fi
      return 0
    }
    xray_config_test_ok() { return 0; }
    xray_installed_version() { printf "25.9.5\n"; }
    self_check_status_summary_tsv() {
      printf "OK\tstatus\t2026-03-26T00:00:00Z\tcfg-1\trecommended\tauto\tipv4\t15\n"
    }
    doctor_measurement_summary_tsv() {
      printf "warning\tpromote-spare\tpromote cfg-2\tok\tok\twatch\tcfg-2\tgreenfam\tfalse\n"
    }

    doctor_flow
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"sudo xray-reality.sh update --replan --non-interactive --yes"* ]]
}
