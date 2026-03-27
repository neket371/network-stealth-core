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

    operator_decision_payload_json() {
      cat <<EOF
{"overall_verdict":"not-installed","next_action":"sudo xray-reality.sh install","runtime":{"managed_present":false}}
EOF
    }
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
    operator_decision_payload_json() {
      cat <<EOF
{"overall_verdict":"broken","next_action":"sudo xray-reality.sh repair --non-interactive --yes","runtime":{"managed_present":true,"service_state":"active","config_state":"ok","transport":"xhttp","installed_version":"25.9.5"},"self_check":{"verdict":"broken","action":"repair","variant_key":"recommended"},"field":{"field_verdict":"unknown","family_diversity_verdict":"unknown","long_term_verdict":"unknown","rotation_verdict":"collect-more-data","primary_weak_streak":0,"best_spare":"n/a","best_spare_family":"n/a"},"decision_recommendation":"unknown","decision_reason":"n/a"}
EOF
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
    operator_decision_payload_json() {
      cat <<EOF
{"overall_verdict":"warning","next_action":"sudo xray-reality.sh update --replan --non-interactive --yes","runtime":{"managed_present":true,"service_state":"active","config_state":"ok","transport":"xhttp","installed_version":"25.9.5"},"self_check":{"verdict":"ok","action":"status","variant_key":"recommended"},"field":{"field_verdict":"warning","coverage_verdict":"ok","family_diversity_verdict":"ok","long_term_verdict":"watch","rotation_verdict":"promote-spare","primary_weak_streak":2,"best_spare":"cfg-2","best_spare_family":"greenfam"},"decision_recommendation":"promote-spare","decision_reason":"promote cfg-2"}
EOF
    }

    doctor_flow
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"sudo xray-reality.sh update --replan --non-interactive --yes"* ]]
    [[ "$output" == *"Rotation: promote-spare | weak streak=2"* ]]
}
