#!/usr/bin/env bats

@test "measure-stealth script exposes help" {
    run bash -eo pipefail -c 'bash ./scripts/measure-stealth.sh --help'
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: scripts/measure-stealth.sh"* ]]
    [[ "$output" == *"scripts/measure-stealth.sh import [options]"* ]]
    [[ "$output" == *"scripts/measure-stealth.sh prune [options]"* ]]
    [[ "$output" == *"--variants <list>"* ]]
}

@test "measurement_compare_reports_json summarizes saved reports" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    report_a="$tmp_dir/a.json"
    report_b="$tmp_dir/b.json"
    cat > "$report_a" <<EOF
{"generated":"2026-03-07T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    cat > "$report_b" <<EOF
{"generated":"2026-03-07T11:00:00Z","network_tag":"mobile","provider":"isp-b","region":"spb","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":false},{"config_name":"Config 2","domain":"yandex.ru","provider_family":"yandex","primary_rank":1,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":false,"latency_ms":0,"reason":"blocked"},{"config_name":"Config 2","variant_key":"recommended","success":true,"latency_ms":140}]}
EOF
    out=$(measurement_compare_reports_json "$report_a" "$report_b")
    jq -e '\''.field_verdict == "warning"'\'' <<< "$out" > /dev/null
    jq -e '\''.best_spare == "Config 2"'\'' <<< "$out" > /dev/null
    jq -e '\''.promotion_candidate.config_name == "Config 2"'\'' <<< "$out" > /dev/null
    jq -e '\''.family_diversity_verdict == "ok" and .config_provider_family_count == 2'\'' <<< "$out" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "measurement_import_report_file stores validated report and refreshes summary" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    MEASUREMENTS_DIR="$tmp_dir/measurements"
    MEASUREMENTS_SUMMARY_FILE="$MEASUREMENTS_DIR/latest-summary.json"
    report="$tmp_dir/report.json"
    cat > "$report" <<EOF
{"generated":"2026-03-08T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    imported=$(measurement_import_report_file "$report")
    imported_path=$(jq -r ".stored_file" <<< "$imported")
    jq -e ".status == \"imported\"" <<< "$imported" > /dev/null
    test -f "$imported_path"
    test -f "$MEASUREMENTS_SUMMARY_FILE"
    jq -e ".report_count == 1" "$MEASUREMENTS_SUMMARY_FILE" > /dev/null
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "measurement_import_report_file returns duplicate without rewriting summary" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    MEASUREMENTS_DIR="$tmp_dir/measurements"
    MEASUREMENTS_SUMMARY_FILE="$MEASUREMENTS_DIR/latest-summary.json"
    report="$tmp_dir/report.json"
    cat > "$report" <<EOF
{"generated":"2026-03-08T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[{"config_name":"Config 1","domain":"vk.com","provider_family":"vk","primary_rank":0,"success":true}],"results":[{"config_name":"Config 1","variant_key":"recommended","success":true,"latency_ms":120}]}
EOF
    first=$(measurement_import_report_file "$report")
    second=$(measurement_import_report_file "$report")
    first_path=$(jq -r ".stored_file" <<< "$first")
    second_path=$(jq -r ".stored_file" <<< "$second")
    jq -e ".status == \"duplicate\"" <<< "$second" > /dev/null
    [[ "$second_path" == "$first_path" ]]
    test -f "$first_path"
    echo ok
   '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "measurement_prune_reports keeps newest reports" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    MEASUREMENTS_DIR="$tmp_dir/measurements"
    MEASUREMENTS_SUMMARY_FILE="$MEASUREMENTS_DIR/latest-summary.json"
    mkdir -p "$MEASUREMENTS_DIR"
    cat > "$MEASUREMENTS_DIR/20260308T090000Z-home-isp-a-msk-a.json" <<EOF
{"generated":"2026-03-08T09:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[],"results":[]}
EOF
    cat > "$MEASUREMENTS_DIR/20260308T100000Z-home-isp-a-msk-b.json" <<EOF
{"generated":"2026-03-08T10:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[],"results":[]}
EOF
    cat > "$MEASUREMENTS_DIR/20260308T110000Z-home-isp-a-msk-c.json" <<EOF
{"generated":"2026-03-08T11:00:00Z","network_tag":"home","provider":"isp-a","region":"msk","configs":[],"results":[]}
EOF
    out=$(measurement_prune_reports 2 false)
    jq -e ".removed_count == 1" <<< "$out" > /dev/null
    test ! -f "$MEASUREMENTS_DIR/20260308T090000Z-home-isp-a-msk-a.json"
    test -f "$MEASUREMENTS_DIR/20260308T100000Z-home-isp-a-msk-b.json"
    test -f "$MEASUREMENTS_DIR/20260308T110000Z-home-isp-a-msk-c.json"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "lab smoke scripts expose help" {
    run bash -eo pipefail -c '
    bash ./scripts/lab/prepare-host-safe-smoke.sh --help
    bash ./scripts/lab/run-container-smoke.sh --help
    bash ./scripts/lab/collect-container-artifacts.sh --help
    bash ./scripts/lab/prepare-vm-smoke.sh --help
    bash ./scripts/lab/run-vm-lifecycle-smoke.sh --help
    bash ./scripts/lab/run-vm-release-smoke.sh --help
    bash ./scripts/lab/collect-vm-artifacts.sh --help
    bash ./scripts/lab/enter-vm-smoke.sh --help
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/lab/run-container-smoke.sh"* ]]
    [[ "$output" == *"scripts/lab/run-vm-lifecycle-smoke.sh"* ]]
    [[ "$output" == *"scripts/lab/run-vm-release-smoke.sh"* ]]
}

@test "lab smoke runs artifact collector through bash" {
    run bash -eo pipefail -c '
    grep -Fq '\''result_json="$(bash "$SCRIPT_DIR/collect-container-artifacts.sh" --timestamp "$timestamp")"'\'' \
      ./scripts/lab/run-container-smoke.sh
    grep -Fq '\''export LANG=C.UTF-8'\'' ./scripts/lab/run-container-smoke.sh
    grep -Fq '\''export LC_ALL=C.UTF-8'\'' ./scripts/lab/run-container-smoke.sh
    grep -Fq '\''result_json="$(bash "$SCRIPT_DIR/collect-vm-artifacts.sh" --timestamp "$timestamp" --guest-ip "$(lab_vm_guest_ipv4)" --smoke-status "$smoke_status")"'\'' \
      ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''bash scripts/lab/guest-vm-lifecycle.sh'\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''guest-vm-release-smoke.sh'\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "update flow verifies listeners before final self-check" {
    run bash -eo pipefail -c '
    awk '\''/update_flow\(\)/, /^repair_flow\(\)/ {print}'\'' ./install.sh | grep -Fq "verify_ports_listening_after_start"
    awk '\''/update_flow\(\)/, /^repair_flow\(\)/ {print}'\'' ./install.sh | grep -Fq "test_reality_connectivity || true"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "vm lab guest defaults pin a deterministic custom domain shortlist" {
    run bash -eo pipefail -c '
    grep -Fq '\''vm_lab_default_custom_domains() {'\'' ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq '\''XRAY_CUSTOM_DOMAINS="$(vm_lab_default_custom_domains)"'\'' ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq '\''XRAY_CUSTOM_DOMAINS='\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''VM_GUEST_MODE=release'\'' ./scripts/lab/run-vm-release-smoke.sh
    grep -Fq '\''RELEASE_TAG='\'' ./scripts/lab/run-vm-release-smoke.sh
    grep -Fq '\''UPDATE_VERSION="$INSTALL_VERSION"'\'' ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq '\''resolved_version="$(resolve_latest_stable_xray_version || true)"'\'' ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq '\''INSTALL_VERSION='\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''UPDATE_VERSION='\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''keep_failure_state="${E2E_KEEP_FAILURE_STATE:-}"'\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    grep -Fq '\''E2E_KEEP_FAILURE_STATE='\'' ./scripts/lab/run-vm-lifecycle-smoke.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "vm lab guest flow installs manual helper commands and hints" {
    run bash -eo pipefail -c '
    grep -Fq "install_guest_manual_helpers() {" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "/usr/local/bin/nsc-vm-install-latest" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "/usr/local/bin/nsc-vm-install-release" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "/usr/local/bin/nsc-vm-install-repo" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "/usr/local/bin/nsc-vm-guest-ip" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "raw curl install внутри этого гостя" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "release/bootstrap validation path" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "ALLOW_INSECURE_SHA256" ./scripts/lab/guest-vm-lifecycle.sh
    grep -Fq "используй nsc-vm-install-latest [--num-configs n|--advanced]" ./scripts/lab/enter-vm-smoke.sh
    grep -Fq "nsc-vm-install-release <tag>" ./scripts/lab/enter-vm-smoke.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "vm lab release smoke target is wired through make and wrapper script" {
    run bash -eo pipefail -c '
    grep -Fq "vm-lab-release-smoke:" ./Makefile
    grep -Fq "run-vm-release-smoke.sh" ./Makefile
    grep -Fq "VM_GUEST_MODE=release" ./scripts/lab/run-vm-release-smoke.sh
    grep -Fq "RELEASE_TAG is required" ./scripts/lab/run-vm-release-smoke.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "prepare_vm_base_image skips download when the base image already exists" {
    run bash -eo pipefail -c '
    tmp_root=$(mktemp -d)
    tmp_bin=$(mktemp -d)
    trap "rm -rf \"$tmp_root\" \"$tmp_bin\"" EXIT

    cat > "${tmp_bin}/curl" <<'\''EOF'\''
#!/usr/bin/env bash
echo "curl must not be called when the base image already exists" >&2
exit 99
EOF
    chmod +x "${tmp_bin}/curl"

    export LAB_HOST_ROOT="$tmp_root"
    export PATH="${tmp_bin}:$PATH"

    source ./scripts/lab/prepare-vm-smoke.sh

    base_image="$(lab_vm_base_image_path)"
    mkdir -p "$(dirname "$base_image")"
    printf "existing-image" > "$base_image"

    result="$(prepare_vm_base_image)"
    [[ "$result" == "$base_image" ]]
    [[ "$(cat "$base_image")" == "existing-image" ]]
    test ! -e "${base_image}.part"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "prepare_vm_base_image fails cleanly when curl leaves no temp image" {
    run bash -eo pipefail -c '
    tmp_root=$(mktemp -d)
    tmp_bin=$(mktemp -d)
    trap "rm -rf \"$tmp_root\" \"$tmp_bin\"" EXIT

    cat > "${tmp_bin}/curl" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${tmp_bin}/curl"

    export LAB_HOST_ROOT="$tmp_root"
    export PATH="${tmp_bin}:$PATH"

    source ./scripts/lab/prepare-vm-smoke.sh

    base_image="$(lab_vm_base_image_path)"
    if prepare_vm_base_image; then
      echo "unexpected-success"
      exit 1
    fi
    test ! -e "$base_image"
    test ! -e "${base_image}.part"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "release smoke accepts quoted XRAY_DOMAINS_FILE persistence" {
    run bash -eo pipefail -c '
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT

    config_env="${tmp_dir}/config.env"
    domains_file="${tmp_dir}/custom-domains.txt"

    cat > "$config_env" <<EOF
XRAY_DOMAINS_FILE="$domains_file"
EOF
    cat > "$domains_file" <<EOF
vk.com
yoomoney.ru
cdek.ru
EOF

    source ./scripts/lab/guest-vm-release-smoke.sh

    XRAY_ENV="$config_env"
    XRAY_MANAGED_CUSTOM_DOMAINS_FILE="$domains_file"
    XRAY_CUSTOM_DOMAINS="vk.com,yoomoney.ru,cdek.ru"

    assert_path_mode_owner() { [[ "$1" == "$domains_file" ]]; }
    run_root() { "$@"; }

    assert_custom_domains_persisted
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lab common accepts lowercase lab_host_root alias" {
    run bash -eo pipefail -c '
    unset LAB_HOST_ROOT
    lab_host_root=/tmp/nsc-lab-alias
    source ./scripts/lab/common.sh
    [ "$(lab_host_root)" = "/tmp/nsc-lab-alias" ]
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "enter vm smoke fails early with clear message when vm-lab state is missing" {
    run bash -eo pipefail -c '
    tmp_root="$(mktemp -d)"
    LAB_HOST_ROOT="$tmp_root" bash ./scripts/lab/enter-vm-smoke.sh 2>&1
  '
    [ "$status" -eq 1 ]
    [[ "$output" == *"vm-lab ssh key not found"* ]]
    [[ "$output" == *"prepare-vm-smoke.sh"* ]]
    [[ "$output" == *"run-vm-lifecycle-smoke.sh"* ]]
}

@test "install contract gate allows fresh install without managed contract" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    XRAY_ENV="$tmp/config.env"
    TRANSPORT="xhttp"
    require_xhttp_transport_contract_for_action install
    echo allowed
  '
    [ "$status" -eq 0 ]
    [ "$output" = "allowed" ]
}

@test "install contract gate blocks legacy managed transport before install flow" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    cat > "$XRAY_CONFIG" <<JSON
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "streamSettings": {
        "network": "grpc",
        "realitySettings": {
          "show": false
        }
      },
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "flow": "xtls-rprx-vision"
          }
        ]
      }
    }
  ]
}
JSON
    TRANSPORT="xhttp"
    if require_xhttp_transport_contract_for_action install; then
      echo "unexpected-success"
      exit 1
    fi
    echo "blocked"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"blocked"* ]]
}

@test "resolve_mirror_base replaces version placeholders" {
    local pattern
    for pattern in "https://x/{{version}}" "https://x/{version}" "https://x/\$version"; do
        run bash -eo pipefail -c 'source ./lib.sh; resolve_mirror_base "$1" "$2"' -- "$pattern" "1.2.3"
        [ "$status" -eq 0 ]
        [ "$output" = "https://x/1.2.3" ]
    done
}

@test "build_mirror_list outputs default and extra mirrors" {
    run bash -eo pipefail -c 'source ./lib.sh; build_mirror_list "https://a/{version}" '\''https://b/{version},https://c/$version'\'' "1.0"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://a/1.0" ]
    [ "${lines[1]}" = "https://b/1.0" ]
    [ "${lines[2]}" = "https://c/1.0" ]
}

@test "xray_geo_dir falls back to XRAY_BIN directory" {
    run bash -eo pipefail -c 'source ./lib.sh; XRAY_BIN="/opt/xray/bin/xray"; XRAY_GEO_DIR=""; xray_geo_dir'
    [ "$status" -eq 0 ]
    [ "$output" = "/opt/xray/bin" ]
}

@test "xray_geo_dir prefers explicit XRAY_GEO_DIR" {
    run bash -eo pipefail -c 'source ./lib.sh; XRAY_BIN="/opt/xray/bin/xray"; XRAY_GEO_DIR="/srv/xray/geo"; xray_geo_dir'
    [ "$status" -eq 0 ]
    [ "$output" = "/srv/xray/geo" ]
}

@test "validate_curl_target rejects non-https url" {
    run bash -eo pipefail -c 'source ./lib.sh; validate_curl_target "http://example.com/a" true'
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects control chars in path vars" {
    run bash -eo pipefail -c 'source ./lib.sh; XRAY_SCRIPT_PATH=$'\''/usr/local/bin/xray-reality.sh\nbad'\''; strict_validate_runtime_inputs install'
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs accepts valid update inputs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_MIRRORS="https://github.com/XTLS/Xray-core/releases/download/v1.0.0"
    MINISIGN_MIRRORS="https://github.com/jedisct1/minisign/releases/download/0.11"
    DOWNLOAD_HOST_ALLOWLIST="github.com,api.github.com"
    strict_validate_runtime_inputs update
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs rejects dangerous XRAY_LOGS for uninstall" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_LOGS="/etc"
    strict_validate_runtime_inputs uninstall
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects dangerous XRAY_LOGS for repair" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_LOGS="/etc"
    strict_validate_runtime_inputs repair
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects dangerous XRAY_LOGS for diagnose" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_LOGS="/etc"
    strict_validate_runtime_inputs diagnose
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects dangerous XRAY_LOGS for rollback" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_LOGS="/etc"
    strict_validate_runtime_inputs rollback
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects non-project XRAY_KEYS path for uninstall" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_KEYS="/etc/ssl"
    strict_validate_runtime_inputs uninstall
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_KEYS"* ]]
}

@test "strict_validate_runtime_inputs rejects non-project XRAY_DATA_DIR for uninstall" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_DATA_DIR="/usr/local/share"
    strict_validate_runtime_inputs uninstall
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_DATA_DIR"* ]]
}

@test "strict_validate_runtime_inputs rejects traversal XRAY_KEYS path escaping to system dir" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_KEYS="/tmp/xray/../../etc/ssh"
    strict_validate_runtime_inputs uninstall
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_KEYS"* ]]
}

@test "strict_validate_runtime_inputs rejects traversal XRAY_CONFIG path escaping to system dir" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_CONFIG="/tmp/reality/../../etc/ssh/config.json"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"XRAY_CONFIG"* ]]
}

@test "strict_validate_runtime_inputs allows custom non-system XRAY_HOME path" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_HOME="/srv/vpn"
    strict_validate_runtime_inputs install
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs allows XRAY_GEO_DIR equal to dirname of XRAY_BIN" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_BIN="/usr/local/bin/xray"
    XRAY_GEO_DIR="/usr/local/bin"
    strict_validate_runtime_inputs update
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs accepts safe nested custom paths for uninstall" {
    run bash -eo pipefail -c '
    source ./lib.sh
    base="$(mktemp -d)"
    XRAY_KEYS="$base/etc/xray/private/keys"
    XRAY_BACKUP="$base/var/backups/xray"
    XRAY_LOGS="$base/var/log/xray"
    XRAY_HOME="$base/var/lib/xray"
    XRAY_DATA_DIR="$base/usr/local/share/xray-reality"
    XRAY_GEO_DIR="$base/usr/local/share/xray"
    XRAY_BIN="$base/usr/local/bin/xray"
    XRAY_CONFIG="$base/etc/xray/config.json"
    XRAY_ENV="$base/etc/xray-reality/config.env"
    XRAY_SCRIPT_PATH="$base/usr/local/bin/xray-reality.sh"
    XRAY_UPDATE_SCRIPT="$base/usr/local/bin/xray-reality-update.sh"
    MINISIGN_KEY="$base/etc/xray/minisign.pub"
    strict_validate_runtime_inputs uninstall
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "uninstall_is_allowed_file_path allows known xray logs in /var/log" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./modules/service/uninstall.sh
    uninstall_is_allowed_file_path /var/log/xray-install.log
    uninstall_is_allowed_file_path /var/log/xray-update.log
    uninstall_is_allowed_file_path /var/log/xray-diagnose.log
    uninstall_is_allowed_file_path /var/log/xray-repair.log
    uninstall_is_allowed_file_path /var/log/xray-health.log
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "uninstall_is_allowed_file_path rejects unrelated /var/log targets" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    uninstall_is_allowed_file_path /var/log/syslog
  '
    [ "$status" -ne 0 ]
}

@test "uninstall_is_allowed_file_path rejects unrelated file in allowed dirname" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    uninstall_is_allowed_file_path /usr/local/bin/sudo
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid primary domain mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PRIMARY_DOMAIN_MODE="broken"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs accepts quarantine and primary controls" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="yandex.ru"
    PRIMARY_ADAPTIVE_TOP_N=10
    DOMAIN_QUARANTINE_FAIL_STREAK=5
    DOMAIN_QUARANTINE_COOLDOWN_MIN=180
    strict_validate_runtime_inputs update
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs rejects invalid DOWNLOAD_HOST_ALLOWLIST host" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOWNLOAD_HOST_ALLOWLIST="github.com,bad/host"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects non-allowlisted geo download url" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOWNLOAD_HOST_ALLOWLIST="github.com,release-assets.githubusercontent.com"
    XRAY_GEOIP_URL="https://example.com/geoip.dat"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid GH_PROXY_BASE url" {
    run bash -eo pipefail -c '
    source ./lib.sh
    GH_PROXY_BASE="http://ghproxy.com/https://github.com"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid PROGRESS_MODE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PROGRESS_MODE="broken"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid HEALTH_CHECK_INTERVAL" {
    run bash -eo pipefail -c '
    source ./lib.sh
    HEALTH_CHECK_INTERVAL="120
ExecStart=/tmp/pwn"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid LOG_MAX_SIZE_MB" {
    run bash -eo pipefail -c '
    source ./lib.sh
    LOG_MAX_SIZE_MB="abc"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid MAX_BACKUPS" {
    run bash -eo pipefail -c '
    source ./lib.sh
    MAX_BACKUPS="abc"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid DOMAIN_CHECK_PARALLELISM" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_CHECK_PARALLELISM=0
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid AUTO_UPDATE_RANDOM_DELAY" {
    run bash -eo pipefail -c '
    source ./lib.sh
    AUTO_UPDATE_RANDOM_DELAY="1h;touch /tmp/pwn"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid AUTO_UPDATE_ONCALENDAR" {
    run bash -eo pipefail -c '
    source ./lib.sh
    AUTO_UPDATE_ONCALENDAR="weekly;touch /tmp/pwn"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs accepts XRAY_DOMAIN_PROFILE global-50" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_DOMAIN_PROFILE="global-50"
    strict_validate_runtime_inputs install
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs keeps legacy XRAY_DOMAIN_PROFILE global-ms10 compatibility" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_DOMAIN_PROFILE="global-ms10"
    strict_validate_runtime_inputs install
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "strict_validate_runtime_inputs rejects invalid XRAY_DOMAIN_PROFILE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    XRAY_DOMAIN_PROFILE="global-ms999"
    strict_validate_runtime_inputs install
  '
    [ "$status" -ne 0 ]
}

@test "apply_runtime_overrides keeps installed tier for add-clients" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="add-clients"
    DOMAIN_TIER="tier_ru"
    XRAY_DOMAIN_PROFILE="global-50"
    apply_runtime_overrides
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier_ru"* ]]
}

@test "apply_runtime_overrides applies XRAY_DOMAIN_PROFILE for install" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="install"
    DOMAIN_TIER="tier_ru"
    XRAY_DOMAIN_PROFILE="global-50"
    apply_runtime_overrides
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "tier_global_ms10" ]
}

@test "apply_runtime_overrides folds XRAY_DOMAIN_TIER into effective DOMAIN_TIER for install" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="install"
    DOMAIN_TIER="tier_ru"
    XRAY_DOMAIN_TIER="global-50-auto"
    apply_runtime_overrides
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "tier_global_ms10" ]
}

@test "apply_runtime_overrides warns for legacy global-ms10 alias and keeps compatibility" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="install"
    DOMAIN_TIER="tier_ru"
    XRAY_DOMAIN_PROFILE="global-ms10"
    apply_runtime_overrides
    echo "tier=$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy-алиасом"* ]]
    [[ "$output" == *"tier=tier_global_ms10"* ]]
}

@test "apply_runtime_overrides rejects explicit legacy transport override for normal v7 action" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="install"
    TRANSPORT="grpc"
    apply_runtime_overrides
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"migrate-stealth"* ]]
}

@test "apply_runtime_overrides allows managed legacy transport for status" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="status"
    TRANSPORT="grpc"
    managed_install_contract_present() { return 0; }
    detect_current_managed_transport() { printf "%s\n" "grpc"; }
    apply_runtime_overrides
    echo "$TRANSPORT"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "grpc" ]
}

@test "apply_runtime_overrides rejects mismatched legacy transport for status" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="status"
    TRANSPORT="grpc"
    managed_install_contract_present() { return 0; }
    detect_current_managed_transport() { printf "%s\n" "xhttp"; }
    apply_runtime_overrides
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"migrate-stealth"* ]]
}

@test "apply_runtime_overrides allows explicit legacy transport for migrate-stealth" {
    run bash -eo pipefail -c '
    source ./lib.sh
    ACTION="migrate-stealth"
    TRANSPORT="grpc"
    apply_runtime_overrides
    echo "$TRANSPORT"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "grpc" ]
}

@test "strict_validate_runtime_inputs rejects invalid XRAY_DOMAINS_FILE domain" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
yandex.ru
bad_domain
EOF
    XRAY_CUSTOM_DOMAINS=""
    XRAY_DOMAINS_FILE="$tmp"
    strict_validate_runtime_inputs install
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects empty XRAY_DOMAINS_FILE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    XRAY_CUSTOM_DOMAINS=""
    XRAY_DOMAINS_FILE="$tmp"
    strict_validate_runtime_inputs install
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs accepts valid XRAY_DOMAINS_FILE" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
yandex.ru
vk.com
EOF
    XRAY_CUSTOM_DOMAINS=""
    XRAY_DOMAINS_FILE="$tmp"
    strict_validate_runtime_inputs install
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "strict_validate_runtime_inputs rejects custom profile without managed source" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="custom"
    XRAY_DOMAIN_PROFILE="custom"
    XRAY_CUSTOM_DOMAINS=""
    XRAY_DOMAINS_FILE=""
    strict_validate_runtime_inputs add-clients
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"custom-domains.txt"* ]]
}

@test "strict_validate_runtime_inputs accepts custom profile with inline domains" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="custom"
    XRAY_DOMAIN_PROFILE="custom"
    XRAY_CUSTOM_DOMAINS="vk.com,yoomoney.ru,cdek.ru"
    XRAY_DOMAINS_FILE=""
    strict_validate_runtime_inputs install
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "strict_validate_runtime_inputs rejects invalid REALITY_TEST_PORTS values" {
    run bash -eo pipefail -c '
    source ./lib.sh
    REALITY_TEST_PORTS="443,70000"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "strict_validate_runtime_inputs rejects invalid PRIMARY_PIN_DOMAIN" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="bad_domain"
    strict_validate_runtime_inputs update
  '
    [ "$status" -ne 0 ]
}

@test "validate_export_json_schema accepts minimal json export" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp=$(mktemp)
    cat > "$tmp" <<EOF
{"profiles":[{"name":"x","vless_link":"vless://demo"}]}
EOF
    validate_export_json_schema "$tmp" "json"
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validate_export_json_schema rejects empty text export" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp=$(mktemp)
    : > "$tmp"
    validate_export_json_schema "$tmp" "text"
  '
    [ "$status" -ne 0 ]
}

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

@test "setup_logrotate uses runtime log path variables" {
    run bash -eo pipefail -c '
    grep -q '\''safe_logs_dir='\'' ./modules/install/bootstrap.sh
    grep -q '\''safe_health_log='\'' ./modules/install/bootstrap.sh
    grep -Fq '\''${safe_logs_dir%/}/access.log ${safe_logs_dir%/}/error.log {'\'' ./modules/install/bootstrap.sh
    grep -Fq '\''create 0640 xray xray'\'' ./modules/install/bootstrap.sh
    grep -Fq '\''${safe_health_log} ${safe_install_log} ${safe_update_log} ${safe_diag_log} ${safe_repair_log} {'\'' ./modules/install/bootstrap.sh
    grep -Fq '\''su root root'\'' ./modules/install/bootstrap.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "temp xray config files use hardened permissions helper" {
    run bash -eo pipefail -c '
    grep -q '\''set_temp_xray_config_permissions "\$tmp_config"'\'' ./config.sh
    grep -q '\''^set_temp_xray_config_permissions() {'\'' ./modules/config/runtime_apply.sh
    ! grep -q '\''chmod 644 "\$tmp_config"'\'' ./config.sh
    ! grep -q '\''chmod 644 "\$tmp_config"'\'' ./modules/config/runtime_apply.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "create_temp_xray_config_file uses TMPDIR and json suffix" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmpdir=$(mktemp -d)
    TMPDIR="$tmpdir"
    tmp_config=$(create_temp_xray_config_file)
    [[ -f "$tmp_config" ]]
    [[ "$tmp_config" == "$tmpdir"/xray-config.*.json ]]
    rm -f "$tmp_config"
    rmdir "$tmpdir"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rpm dependency check accepts curl provider even without curl package" {
    run bash -eo pipefail -c '
    source ./modules/install/bootstrap.sh
    log() { :; }
    PKG_TYPE="rpm"
    PKG_UPDATE=":"
    PKG_INSTALL="false"
    rpm() {
      [[ "$1" == "-q" ]] || return 1
      case "$2" in
        curl) return 1 ;;
        curl-minimal|jq|openssl|unzip|ca-certificates|util-linux|iproute|procps-ng|libcap|logrotate|policycoreutils) return 0 ;;
        *) return 1 ;;
      esac
    }
    install_dependencies
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "e2e run_root prefers direct execution as root and falls back to sudo -n" {
    run bash -eo pipefail -c '
    grep -q '\''EUID'\'' ./tests/e2e/lib.sh
    grep -q '\''sudo -n true'\'' ./tests/e2e/lib.sh
    grep -q '\''sudo -n "\$@"'\'' ./tests/e2e/lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "derive_public_key_from_private_key uses strict x25519 -i flow" {
    run bash -eo pipefail -c '
    grep -q '\''x25519 -i "\$private_key"'\'' ./modules/config/client_state.sh
    ! grep -q '\''x25519 "\$private_key"'\'' ./modules/config/client_state.sh
    grep -q '\''xray x25519 -i failed while deriving public key'\'' ./modules/config/client_state.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "build_config validates IPv6 port presence before jq tonumber" {
    run bash -eo pipefail -c '
    grep -q '\''if \[\[ -z "\${PORTS_V6\[\$i\]:-}" \]\]'\'' ./config.sh
    grep -q '\''HAS_IPV6=true, но IPv6 порт для конфига'\'' ./config.sh
    grep -q '\''Ошибка генерации IPv6 inbound для конфига'\'' ./config.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "build_add_clients_inbounds validates IPv6 jq conversion and payload assembly" {
    run bash -eo pipefail -c '
    grep -q '\''if ! inbound_v6=$(echo "\$inbound_v4" | jq --arg port "\${_new_ports_v6\[\$i\]}"'\'' ./modules/config/add_clients.sh
    grep -q '\''Ошибка генерации IPv6 inbound для add-clients config'\'' ./modules/config/add_clients.sh
    grep -Fq '\''if ! inbounds_payload=$(jq -s '\'' ./modules/config/add_clients.sh
    grep -Fq '\''"$tmp_inbounds" 2> /dev/null); then'\'' ./modules/config/add_clients.sh
    grep -q '\''Ошибка сборки add-clients inbounds payload'\'' ./modules/config/add_clients.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "update_xray backs up config and client artifacts before update" {
    run bash -eo pipefail -c '
    grep -q '\''for artifact in'\'' ./modules/service/runtime.sh
    grep -q '\''"\$XRAY_CONFIG"'\'' ./modules/service/runtime.sh
    grep -q '\''"\$XRAY_KEYS/keys.txt"'\'' ./modules/service/runtime.sh
    grep -q '\''"\$XRAY_KEYS/clients.txt"'\'' ./modules/service/runtime.sh
    grep -q '\''"\$XRAY_KEYS/clients.json"'\'' ./modules/service/runtime.sh
    grep -q '\''backup_file "\$artifact"'\'' ./modules/service/runtime.sh
    grep -q '\''backup_file "\$XRAY_BIN"'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release policy gate accepts valid checksum matrix and sbom" {
    run bash -eo pipefail -c '
    tmpdir=$(mktemp -d)
    script_path="$PWD/scripts/release-policy-gate.sh"
    archive="xray-reality-v0.0.1.tar.gz"
    checksum="xray-reality-v0.0.1.sha256"
    matrix="matrix-result.json"
    sbom="xray-reality-v0.0.1.spdx.json"
    printf "release-asset" > "$tmpdir/$archive"
    archive_sha=$(sha256sum "$tmpdir/$archive" | awk "{print \$1}")
    printf "%s  %s\n" "$archive_sha" "$archive" > "$tmpdir/$checksum"
    printf "%s\n" "[{\"name\":\"ubuntu-24.04\",\"status\":\"success\"}]" > "$tmpdir/$matrix"
    printf "%s\n" "{\"spdxVersion\":\"SPDX-2.3\",\"SPDXID\":\"SPDXRef-DOCUMENT\",\"creationInfo\":{\"created\":\"2026-02-19T00:00:00Z\"},\"packages\":[],\"files\":[]}" > "$tmpdir/$sbom"
    (cd "$tmpdir" && bash "$script_path" \
      --tag v0.0.1 \
      --archive "$archive" \
      --checksum "$checksum" \
      --matrix "$matrix" \
      --sbom "$sbom")
    rm -rf "$tmpdir"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "release policy gate rejects failed matrix entries" {
    run bash -eo pipefail -c '
    tmpdir=$(mktemp -d)
    script_path="$PWD/scripts/release-policy-gate.sh"
    archive="xray-reality-v0.0.1.tar.gz"
    checksum="xray-reality-v0.0.1.sha256"
    matrix="matrix-result.json"
    sbom="xray-reality-v0.0.1.spdx.json"
    printf "release-asset" > "$tmpdir/$archive"
    archive_sha=$(sha256sum "$tmpdir/$archive" | awk "{print \$1}")
    printf "%s  %s\n" "$archive_sha" "$archive" > "$tmpdir/$checksum"
    printf "%s\n" "[{\"name\":\"ubuntu-24.04\",\"status\":\"failure\"}]" > "$tmpdir/$matrix"
    printf "%s\n" "{\"spdxVersion\":\"SPDX-2.3\",\"SPDXID\":\"SPDXRef-DOCUMENT\",\"creationInfo\":{\"created\":\"2026-02-19T00:00:00Z\"},\"packages\":[],\"files\":[]}" > "$tmpdir/$sbom"
    if (cd "$tmpdir" && bash "$script_path" \
      --tag v0.0.1 \
      --archive "$archive" \
      --checksum "$checksum" \
      --matrix "$matrix" \
      --sbom "$sbom"); then
      echo "unexpected-success"
      exit 1
    fi
    rm -rf "$tmpdir"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "apply_validated_config accepts successful xray test without marker string" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp)
    target=$(mktemp)
    trap "rm -f \"$tmp\" \"$target\"" EXIT
    echo "{\"inbounds\":[]}" > "$tmp"
    XRAY_CONFIG="$target"
    XRAY_GROUP="xray"
    xray_config_test_file() { echo "ok-without-marker"; return 0; }
    chown() { :; }

    apply_validated_config "$tmp"
    [[ -f "$XRAY_CONFIG" ]]
    grep -q "\"inbounds\"" "$XRAY_CONFIG"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "apply_validated_config rejects non-zero xray test even with marker text" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp)
    target=$(mktemp)
    trap "rm -f \"$tmp\" \"$target\"" EXIT
    echo "{\"inbounds\":[]}" > "$tmp"
    XRAY_CONFIG="$target"
    XRAY_GROUP="xray"
    xray_config_test_file() { echo "Configuration OK"; return 1; }
    chown() { :; }

    if apply_validated_config "$tmp"; then
      echo "unexpected-success"
      exit 1
    fi
    [[ ! -f "$tmp" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "runtime flows use exit-code config check helper instead of marker grep" {
    run bash -eo pipefail -c '
    ! grep -q '\''xray_config_test 2>&1 | grep -q "Configuration OK"'\'' ./install.sh
    ! grep -q '\''xray_config_test 2>&1 | grep -q "Configuration OK"'\'' ./service.sh
    ! grep -q '\''xray_config_test 2>&1 | grep -q "Configuration OK"'\'' ./health.sh
    ! grep -q '\''xray_config_test 2>&1 | grep -q "Configuration OK"'\'' ./lib.sh
    grep -q '\''^xray_config_test_ok() {'\'' ./modules/config/runtime_apply.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "xray_config_test_file falls back to sudo when runuser fails" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    XRAY_USER="xray"
    XRAY_BIN="/usr/local/bin/xray"
    runuser() { return 1; }
    sudo() { echo "sudo-called:$*"; return 0; }
    su() { echo "su-called:$*"; return 99; }
    xray_config_test_file "/tmp/xray-config.json"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo-called:-n -u xray -- /usr/local/bin/xray -test -c /tmp/xray-config.json"* ]]
}

@test "xray_config_test_file falls back to su when runuser and sudo fail" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    XRAY_USER="xray"
    XRAY_BIN="/usr/local/bin/xray"
    runuser() { return 1; }
    sudo() { return 1; }
    su() { echo "su-called:$*"; return 0; }
    xray_config_test_file "/tmp/xray-config.json"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"su-called:-s /bin/sh xray -c \"\$0\" -test -c \"\$1\" /usr/local/bin/xray /tmp/xray-config.json"* ]]
}

@test "xray_config_test_file falls back to root execution when user switches fail" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    XRAY_USER="xray"
    runuser() { return 1; }
    sudo() { return 1; }
    su() { return 1; }
    tmpbin=$(mktemp)
    trap "rm -f \"$tmpbin\"" EXIT
    cat > "$tmpbin" <<'\''EOF'\''
#!/usr/bin/env bash
echo "root-fallback:$*"
exit 0
EOF
    chmod +x "$tmpbin"
    XRAY_BIN="$tmpbin"
    xray_config_test_file "/tmp/xray-config.json"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"root-fallback:-test -c /tmp/xray-config.json"* ]]
}

@test "install_xray trap restore does not use eval" {
    run bash -eo pipefail -c '
    ! grep -q '\''eval "\${_prev_return_trap}"'\'' ./modules/install/xray_runtime.sh
    grep -q '\''trap cleanup_install_xray_tmp RETURN'\'' ./modules/install/xray_runtime.sh
    grep -q '\''trap - RETURN'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install_minisign supports MINISIGN_BIN override path" {
    run bash -eo pipefail -c '
    grep -q '\''local minisign_bin="\${MINISIGN_BIN:-/usr/local/bin/minisign}"'\'' ./modules/install/xray_runtime.sh
    grep -q '\''install -m 755 "\$bin_path" "\$minisign_bin"'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install_xray can use MINISIGN_BIN for signature verification" {
    run bash -eo pipefail -c '
    grep -q '\''local minisign_cmd="minisign"'\'' ./modules/install/xray_runtime.sh
    grep -q '\''if \[\[ -n "\${MINISIGN_BIN:-}" && -x "\${MINISIGN_BIN}" \]\]'\'' ./modules/install/xray_runtime.sh
    grep -q '\''if "\$minisign_cmd" -Vm "\$zip_file" -p "\$MINISIGN_KEY" -x "\$sig_file"'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install_xray suppresses noisy curl 404 lines for optional minisign lookup" {
    run bash -eo pipefail -c '
    grep -Fq '\''sig_err_file=$(mktemp "${tmp_workdir}/xray-${version}.XXXXXX.sigerr"'\'' ./modules/install/xray_runtime.sh
    grep -Fq '\''download_file_allowlist "${base}/Xray-linux-${arch}.zip.minisig" "$sig_file" "Скачиваем minisign подпись..." 2> "$sig_err_file"'\'' ./modules/install/xray_runtime.sh
    grep -Fq '\''debug_file "official minisign signature missing at ${base} (404)"'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install supports strict minisign mode with pinned key fingerprint" {
    run bash -eo pipefail -c '
    grep -q '\''REQUIRE_MINISIGN'\'' ./modules/install/xray_runtime.sh
    grep -q '\''XRAY_MINISIGN_PUBKEY_SHA256'\'' ./modules/install/xray_runtime.sh
    grep -q '\''write_pinned_minisign_key()'\'' ./modules/install/xray_runtime.sh
    grep -q '\''handle_minisign_unavailable()'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "handle_minisign_unavailable fails in strict mode without unsafe override" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    log() { :; }
    hint() { :; }
    REQUIRE_MINISIGN=true
    ALLOW_INSECURE_SHA256=false
    SKIP_MINISIGN=false
    if handle_minisign_unavailable "test"; then
      echo "unexpected-success"
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "handle_minisign_unavailable allows explicit unsafe SHA256 fallback" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    log() { :; }
    hint() { :; }
    REQUIRE_MINISIGN=true
    ALLOW_INSECURE_SHA256=true
    SKIP_MINISIGN=false
    handle_minisign_unavailable "test"
    echo "$SKIP_MINISIGN"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "handle_minisign_unavailable fails in non-interactive mode without unsafe override" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    log() { :; }
    hint() { :; }
    REQUIRE_MINISIGN=false
    ALLOW_INSECURE_SHA256=false
    NON_INTERACTIVE=true
    ASSUME_YES=true
    SKIP_MINISIGN=false
    if handle_minisign_unavailable "test"; then
      echo "unexpected-success"
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "detect_ips ignores invalid auto-detected ipv6" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    log() { :; }
    fetch_ip() {
      if [[ "$1" == "4" ]]; then
        echo "1.2.3.4"
      else
        echo "bad-ip"
      fi
    }
    SERVER_IP=""
    SERVER_IP6=""
    detect_ips > /dev/null
    echo "${HAS_IPV6}:${SERVER_IP6:-empty}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "false:empty" ]
}

@test "validate_clients_json_file accepts object with configs array" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
{"schema_version":2,"transport":"xhttp","configs":[]}
EOF
    validate_clients_json_file "$tmp"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validate_clients_json_file reinitializes invalid clients.json shape" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
      fi
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
{"profiles":{}}
EOF
    validate_clients_json_file "$tmp"
    jq -e '\''type=="object" and (.configs|type=="array") and (.configs|length==0)'\'' "$tmp" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validate_clients_json_file normalizes legacy array format" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
      fi
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
[{"name":"Config 1"}]
EOF
    validate_clients_json_file "$tmp"
    jq -e '\''type=="object" and (.configs|type=="array") and (.configs|length==1) and (.configs[0].variants|length==1)'\'' "$tmp" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validate_clients_json_file normalizes legacy profiles format" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
      fi
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
{"profiles":[{"name":"Config 1"}]}
EOF
    validate_clients_json_file "$tmp"
    jq -e '\''type=="object" and (.configs|type=="array") and (.configs|length==1) and (has("profiles")|not) and (.configs[0].variants|length==1)'\'' "$tmp" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "secure_clients_json_permissions enforces mode 640" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT

    chmod 600 "$tmp" 2> /dev/null || { echo "skip-perms"; exit 0; }
    probe_600=$(stat -c "%a" "$tmp" 2> /dev/null || true)
    chmod 644 "$tmp" 2> /dev/null || { echo "skip-perms"; exit 0; }
    probe_644=$(stat -c "%a" "$tmp" 2> /dev/null || true)
    if [[ "$probe_600" != "600" || "$probe_644" != "644" ]]; then
      echo "skip-perms"
      exit 0
    fi

    chmod 644 "$tmp"
    secure_clients_json_permissions "$tmp"
    mode=$(stat -c "%a" "$tmp")
    [[ "$mode" == "640" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" || "$output" == "skip-perms" ]]
}

@test "validate_clients_json_file keeps normalized file mode 640" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
      fi
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT

    chmod 600 "$tmp" 2> /dev/null || { echo "skip-perms"; exit 0; }
    probe_600=$(stat -c "%a" "$tmp" 2> /dev/null || true)
    chmod 644 "$tmp" 2> /dev/null || { echo "skip-perms"; exit 0; }
    probe_644=$(stat -c "%a" "$tmp" 2> /dev/null || true)
    if [[ "$probe_600" != "600" || "$probe_644" != "644" ]]; then
      echo "skip-perms"
      exit 0
    fi

    cat > "$tmp" <<EOF
{"profiles":[{"name":"Config 1"}]}
EOF
    chmod 666 "$tmp"
    validate_clients_json_file "$tmp"
    mode=$(stat -c "%a" "$tmp")
    [[ "$mode" == "640" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* || "$output" == "skip-perms" ]]
}

@test "ufw delete operations are non-interactive" {
    run bash -eo pipefail -c '
    grep -q "ufw --force delete allow" ./modules/lib/firewall.sh
    grep -q "ufw --force delete allow" ./modules/service/uninstall.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "add_clients_flow backs up artifacts before write" {
    run bash -eo pipefail -c '
    grep -q '\''backup_file "\$keys_file"'\'' ./modules/config/add_clients.sh
    grep -q '\''rebuild_client_artifacts_from_config || {'\'' ./modules/config/add_clients.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "firewall helper records v6 rules with correct family tags" {
    run bash -eo pipefail -c '
    grep -q '\''record_firewall_rule_add "ufw" "\$port" "v6"'\'' ./modules/lib/firewall.sh
    grep -q '\''record_firewall_rule_add "firewalld" "\$port" "v6"'\'' ./modules/lib/firewall.sh
    grep -q '\''record_firewall_rule_add "ip6tables" "\$port" "v6"'\'' ./modules/lib/firewall.sh
    grep -q '\''open_firewall_ports'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "add_clients_flow validates SERVER_IP before link generation" {
    run bash -eo pipefail -c '
    grep -q '\''is_valid_ipv4 "\$SERVER_IP"'\'' ./modules/config/add_clients.sh
    grep -qi '\''не удалось определить корректный ipv4 для add-clients/add-keys'\'' ./modules/config/add_clients.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "bounded restart helper is centralized and reused across flows" {
    run bash -eo pipefail -c '
    grep -q '\''systemctl_restart_xray_bounded()'\'' ./modules/lib/system_runtime.sh
    grep -q '\''XRAY_SYSTEMCTL_RESTART_TIMEOUT'\'' ./modules/lib/system_runtime.sh
    grep -q '\''timeout --signal=TERM --kill-after=15s'\'' ./modules/lib/system_runtime.sh
    grep -q '\''if ! systemctl_restart_xray_bounded restart_err; then'\'' ./modules/service/runtime.sh
    grep -q '\''if ! systemctl_restart_xray_bounded; then'\'' ./modules/config/add_clients.sh
    grep -q '\''if systemctl_restart_xray_bounded; then'\'' ./modules/lib/lifecycle.sh
    ! grep -q '\''systemctl restart xray'\'' ./modules/config/add_clients.sh
    ! grep -q '\''systemctl restart xray'\'' ./modules/lib/lifecycle.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "common bounded systemctl helper is used for daemon-reload and timers" {
    run bash -eo pipefail -c '
    grep -Fq '\''systemctl_run_bounded()'\'' ./modules/lib/system_runtime.sh
    grep -Fq '\''if [[ $# -ge 2 && "$1" == "--err-var" ]]; then'\'' ./modules/lib/system_runtime.sh
    grep -Fq '\''printf -v "$out_err_var"'\'' ./modules/lib/system_runtime.sh
    grep -Fq '\''XRAY_SYSTEMCTL_OP_TIMEOUT'\'' ./modules/lib/system_runtime.sh
    grep -Fq '\''timeout --signal=TERM --kill-after=10s'\'' ./modules/lib/system_runtime.sh
    grep -Fq '\''systemctl_run_bounded --err-var daemon_reload_err daemon-reload'\'' ./modules/service/runtime.sh
    grep -Fq '\''systemctl_run_bounded --err-var enable_err enable xray'\'' ./modules/service/runtime.sh
    grep -Fq '\''if systemctl_run_bounded daemon-reload; then'\'' ./modules/service/runtime.sh
    grep -Fq '\''if ! systemctl_run_bounded daemon-reload; then'\'' ./modules/lib/lifecycle.sh
    grep -Fq '\''if ! systemctl_run_bounded daemon-reload; then'\'' ./health.sh
    grep -Fq '\''if systemctl_run_bounded enable --now xray-health.timer; then'\'' ./health.sh
    grep -Fq '\''if ! systemctl_run_bounded daemon-reload; then'\'' ./modules/install/bootstrap.sh
    grep -Fq '\''if systemctl_run_bounded enable --now xray-auto-update.timer; then'\'' ./modules/install/bootstrap.sh
    grep -Fq '\''if ! systemctl_run_bounded disable --now xray-auto-update.timer; then'\'' ./modules/install/bootstrap.sh
    ! grep -Fq '\''daemon_reload_err=$(systemctl daemon-reload 2>&1)'\'' ./modules/service/runtime.sh
    ! grep -Fq '\''enable_err=$(systemctl enable xray 2>&1)'\'' ./modules/service/runtime.sh
    ! grep -Fq '\''if systemctl daemon-reload > /dev/null 2>&1; then'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "interactive prompts use shared tty helpers with explicit fd reads" {
    run bash -eo pipefail -c '
    grep -Fq "open_interactive_tty_fd() {" ./modules/lib/tty.sh
    grep -Fq "open_interactive_tty_fds() {" ./modules/lib/tty.sh
    grep -Fq "tty_printf() {" ./modules/lib/tty.sh
    grep -Fq "tty_print_line() {" ./modules/lib/tty.sh
    grep -Fq "tty_print_box() {" ./modules/lib/tty.sh
    grep -Fq "open_interactive_tty_fds tty_read_fd tty_write_fd" ./modules/install/selection.sh
    grep -Fq "printf \"Профиль [1/2/3/4]: \" >&\"\$tty_write_fd\"" ./modules/install/selection.sh
    grep -Fq "read -r -u \"\$tty_read_fd\" input" ./modules/install/selection.sh
    grep -Fq "prompt_yes_no_from_tty() {" ./modules/lib/tty.sh
    grep -Fq "extract_confirmation_token_tail() {" ./modules/lib/tty.sh
    grep -Fq "extract_confirmation_token_from_prompt_echo_followup() {" ./modules/lib/tty.sh
    grep -Fq "resolve_confirmation_token() {" ./modules/lib/tty.sh
    grep -Fq "prompt_yes_no_from_tty \"\$tty_read_fd\" \"Подтвердите (yes/no): \" \"Введите yes или no (без кавычек)\" \"\$tty_write_fd\"" ./modules/install/xray_runtime.sh
    grep -Fq "printf \"Количество конфигов (1-%s): \" \"\$max_configs\" >&\"\$tty_write_fd\"" ./modules/install/selection.sh
    grep -Fq "printf \"Количество конфигов добавить (1-%s): \" \"\$max_add\" >&\"\$tty_write_fd\"" ./modules/config/add_clients.sh
    grep -Fq "tty_print_box \"\$tty_write_fd\" \"\$RED\" \"\$uninstall_title\" 60 90" ./modules/service/uninstall.sh
    grep -Fq "Вы уверены? Введите yes для подтверждения или no для отмены:" ./modules/service/uninstall.sh
    grep -Fq "prompt_yes_no_from_tty \\" ./modules/service/uninstall.sh
    grep -Fq "\"Введите yes или no (без кавычек)\"" ./modules/service/uninstall.sh
    ! grep -Fq "if ! prompt_yes_no_from_tty" ./modules/service/uninstall.sh
    grep -Fq "open_interactive_tty_fds tty_read_fd tty_write_fd" ./lib.sh
    grep -Fq "Укажите путь вручную для %s:" ./lib.sh
    grep -Fq "read -r -u \"\$tty_read_fd\" custom_path" ./lib.sh
    grep -Fq "Запускаем transport-aware self-check..." ./install.sh
    grep -Fq "transport-aware self-check: проверяем exported client variants..." ./modules/health/self_check.sh
    ! grep -Fq "read -r -p \"Профиль [1/2/3/4]: \" input < /dev/tty" ./modules/install/selection.sh
    ! grep -Fq "read -r -u \"\$tty_fd\" -p \"Подтвердите (yes/no): \" answer" ./modules/install/xray_runtime.sh
    ! grep -Fq "read -r -p \"Сколько конфигов создать? (1-\${max_configs}): \" input < /dev/tty" ./modules/install/selection.sh
    ! grep -Fq "read -r -p \"Сколько конфигов добавить? (1-\${max_add}): \" input < /dev/tty" ./modules/config/add_clients.sh
    ! grep -Fq "read -r -u \"\$tty_fd\" -p \"Вы уверены? Введите yes для подтверждения или no для отмены: \" confirm" ./modules/service/uninstall.sh
    ! grep -Fq "read -r -u \"\$tty_fd\" confirm" ./modules/service/uninstall.sh
    ! grep -Fq "read -r -u \"\$tty_fd\" -p \"  Укажите путь вручную для \${description}: \" custom_path" ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "ui_box_line_string clips long text and keeps box width stable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    top=$(ui_box_border_string top 10)
    line=$(ui_box_line_string "abcdefghijklmnopqrstuvwxyz" 10)
    [ "${#line}" -eq 12 ]
    [ "${#top}" -eq "${#line}" ]
    [[ "$line" == *"..."* ]]
    [[ "${line:0:1}" == "|" ]]
    [[ "${line: -1}" == "|" ]]
    top_ru=$(ui_box_border_string top 32)
    line_ru=$(ui_box_line_string "Config 2: megafon.ru ~ РЕЗЕРВНЫЙ" 32)
    [ "${#top_ru}" -eq "${#line_ru}" ]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "ui_box_line_string keeps right border stable for cyrillic text in C locale" {
    run bash -eo pipefail -c '
    export LC_ALL=C
    export LANG=C
    source ./lib.sh
    line=$(ui_box_line_string "Config 1: yandex.ru * ГЛАВНЫЙ" 32)
    top=$(ui_box_border_string top 32)
    [ "$(ui_box_text_length "$line")" -eq "$(ui_box_text_length "$top")" ]
    [[ "${line:0:1}" == "|" ]]
    [[ "${line: -1}" == "|" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "clients header box writes one line per segment" {
    run bash -eo pipefail -c '
    grep -Fq "printf '\''%s\\n'\'' \"\$(ui_box_border_string top \"\$header_width\")\"" ./modules/config/client_formats.sh
    grep -Fq "printf '\''%s\\n'\'' \"\$(ui_box_line_string \"\$header_title\" \"\$header_width\")\"" ./modules/config/client_formats.sh
    grep -Fq "printf '\''%s\\n'\'' \"\$(ui_box_border_string bottom \"\$header_width\")\"" ./modules/config/client_formats.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "format_generated_timestamp avoids double spaces before day" {
    run bash -eo pipefail -c '
    source ./lib.sh
    stamp=$(format_generated_timestamp)
    [[ "$stamp" != *"  "* ]]
    printf "%s\n" "$stamp" | grep -Eq "^[A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} (AM|PM) .+ [0-9]{4}$"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "clients summary keeps concise management commands" {
    run bash -eo pipefail -c '
    grep -Fq -- "- обновить: xray-reality.sh update" ./modules/config/client_formats.sh
    grep -Fq -- "- удалить: xray-reality.sh uninstall" ./modules/config/client_formats.sh
    ! grep -Fq "Для обновления Xray до новой версии выполните: sudo xray-reality.sh update" ./modules/config/client_formats.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "config uses formatted generated timestamp helper" {
    run bash -eo pipefail -c '
    grep -Fq "[[ -n \"\$generated\" ]] || generated=\"\$(format_generated_timestamp)\"" ./modules/config/client_formats.sh
    grep -Fq "Generated: \$(format_generated_timestamp)" ./modules/config/client_formats.sh
    grep -Fq -- "--arg generated \"\$(format_generated_timestamp)\"" ./modules/config/client_formats.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "yes/no parser normalizes trim and carriage return" {
    run bash -eo pipefail -c '
    source ./lib.sh
    is_yes_input "yes"$'\''\r'\''
    is_yes_input "  YES  "
    is_yes_input "y e s"
    is_yes_input $'\''\e[200~yes\e[201~'\''
    is_yes_input $'\''\e]0;title\a yes'\''
    is_yes_input "yеs"
    is_yes_input "уес"
    is_no_input " no "$'\''\r'\''
    is_no_input " n o "
    is_no_input "nо"
    is_no_input "НЕТ"
    is_no_input "н е т"
    is_no_input "но"
    ! is_yes_input "maybe"
    ! is_yes_input "yesplease"
    ! is_no_input "1"
    ! is_no_input "north"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "normalize_tty_input strips CSI OSC and control artifacts" {
    run bash -eo pipefail -c '
    source ./lib.sh
    a=$(normalize_tty_input $'\''\e[31myes\e[0m'\'')
    b=$(normalize_tty_input $'\''\e]0;title\a yes'\'')
    c=$(normalize_tty_input $'\''\e]0;title\e\\yes'\'')
    d=$(normalize_tty_input $'\''\b\byes\t'\'')
    e=$(normalize_tty_input $'\''\u200Fyes\u00A0'\'')
    [[ "$a" == "yes" ]]
    [[ "$b" == "yes" ]]
    [[ "$c" == "yes" ]]
    [[ "$d" == "yes" ]]
    [[ "$e" == "yes" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "canonicalize_confirmation_token handles mixed alphabet answers" {
    run bash -eo pipefail -c '
    source ./lib.sh
    [[ "$(canonicalize_confirmation_token "уес")" == "yes" ]]
    [[ "$(canonicalize_confirmation_token "nо")" == "no" ]]
    [[ "$(canonicalize_confirmation_token "НЕТ")" == "net" ]]
    [[ "$(canonicalize_confirmation_token "но")" == "no" ]]
    [[ "$(canonicalize_confirmation_token "d-a")" == "da" ]]
    [[ "$(canonicalize_confirmation_token "\"yes\"")" == "yes" ]]
    [[ "$(canonicalize_confirmation_token "[ no ]")" == "no" ]]
    sq=$(printf "\\047")
    bq=$(printf "\\140")
    [[ "$(canonicalize_confirmation_token "${sq}yes${sq}")" == "yes" ]]
    [[ "$(canonicalize_confirmation_token "${bq}yes${bq}")" == "yes" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "extract_confirmation_token_tail keeps only trailing yes-no answer" {
    run bash -eo pipefail -c '
    source ./lib.sh
    [[ "$(extract_confirmation_token_tail "Вы уверены? Введите yes для подтверждения или no для отмены: yes")" == "yes" ]]
    [[ "$(extract_confirmation_token_tail "Подтвердите (yes/no): no")" == "no" ]]
    [[ "$(extract_confirmation_token_tail "Вы уверены? Введите yes для подтверждения или no для отмены yes")" == "yes" ]]
    [[ "$(extract_confirmation_token_tail "Подтвердите (yes/no) no")" == "no" ]]
    [[ -z "$(extract_confirmation_token_tail "Вы уверены? Введите yes для подтверждения или no для отмены:")" ]]
    [[ -z "$(extract_confirmation_token_tail "random text yes maybe")" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "resolve_confirmation_token accepts prompt line with trailing answer after extra question text" {
    run bash -eo pipefail -c '
    source ./lib.sh
    [[ "$(resolve_confirmation_token "Продолжить установку только по SHA256? Подтвердите (yes/no): yes")" == "yes" ]]
    [[ "$(resolve_confirmation_token "Minisign подпись не найдена. Подтвердите (yes/no): no")" == "no" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "open_interactive_tty_fd fails quietly without controlling tty" {
    run bash -eo pipefail -c '
    source ./lib.sh
    if open_interactive_tty_fd fd; then
      echo "unexpected-success"
      exit 1
    fi
    [[ -z "${fd:-}" ]]
  '
    [ "$status" -eq 0 ]
    [[ "$output" != *"/dev/tty"* ]]
}

@test "prompt_yes_no_from_tty accepts yes without retry" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "yes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty accepts no without retry" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tty_printf() { :; }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "no\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=1" ]
}

@test "prompt_yes_no_from_tty accepts quoted yes without retry" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "\"yes\"\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty retries invalid then accepts no" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "abc\nно\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=1 retry=1" ]
}

@test "prompt_yes_no_from_tty accepts echoed prompt prefix without retry" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "Вы уверены? Введите yes для подтверждения или no для отмены: yes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Вы уверены? Введите yes для подтверждения или no для отмены: " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty accepts echoed prompt prefix without delimiter" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "Вы уверены? Введите yes для подтверждения или no для отмены yes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Вы уверены? Введите yes для подтверждения или no для отмены: " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty tolerates leaked prompt echo before yes" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "Подтвердите (yes/no):\nyes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty accepts prompt line with extra question text and trailing yes" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "Продолжить установку только по SHA256? Подтвердите (yes/no): yes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=0" ]
}

@test "prompt_yes_no_from_tty retries invalid then accepts yes" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "abc\nyes\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Подтвердите (yes/no): " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rc=0 retry=1" ]
}

@test "prompt_yes_no_from_tty rejects prompt-only line without answer" {
    run bash -eo pipefail -c '
    source ./lib.sh
    retry_count=0
    tty_printf() {
      if [[ "${3:-}" == "Введите yes или no (без кавычек)" ]]; then
        retry_count=$((retry_count + 1))
      fi
      :
    }
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    printf "Вы уверены? Введите yes для подтверждения или no для отмены:\n" > "$tmp"
    exec 9<"$tmp"
    if prompt_yes_no_from_tty 9 "Вы уверены? Введите yes для подтверждения или no для отмены: " "Введите yes или no (без кавычек)"; then
      rc=0
    else
      rc=$?
    fi
    echo "rc=$rc retry=$retry_count"
  '
    [ "$status" -eq 0 ]
}

@test "ui_box_width_for_lines respects min and max bounds" {
    run bash -eo pipefail -c '
    source ./lib.sh
    [ "$(ui_box_width_for_lines 60 80 "short")" = "60" ]
    [ "$(ui_box_width_for_lines 10 20 "1234567890123456789012345")" = "20" ]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "ui_box_width_for_lines clamps to tty width override" {
    run bash -eo pipefail -c '
    source ./lib.sh
    UI_BOX_TTY_COLS=42
    [ "$(ui_box_width_for_lines 60 90 "abcdefghijklmnopqrstuvwxyz")" = "40" ]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "format_russian_count_noun uses correct config grammar" {
    run bash -eo pipefail -c '
    source ./lib.sh
    [[ "$(format_russian_count_noun 1 "конфиг" "конфига" "конфигов")" == "1 конфиг" ]]
    [[ "$(format_russian_count_noun 2 "конфиг" "конфига" "конфигов")" == "2 конфига" ]]
    [[ "$(format_russian_count_noun 5 "конфиг" "конфига" "конфигов")" == "5 конфигов" ]]
    [[ "$(format_russian_count_noun 11 "конфиг" "конфига" "конфигов")" == "11 конфигов" ]]
    [[ "$(format_russian_count_noun 21 "конфиг" "конфига" "конфигов")" == "21 конфиг" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install result prints russian quick start instead of dumping full links file" {
    run bash -eo pipefail -c "grep -Fq 'INSTALL_OUTPUT_MODULE=\"\$SCRIPT_DIR/modules/install/output.sh\"' ./install.sh; grep -Fq 'source \"\$INSTALL_OUTPUT_MODULE\"' ./install.sh; grep -Fq 'build_install_quick_start_file()' ./modules/install/output.sh; grep -Fq 'header_text=' ./modules/install/output.sh; grep -Fq 'все ссылки: \${XRAY_KEYS}/clients-links.txt' ./modules/install/output.sh; echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "clients summary points operators to russian links guidance" {
    run bash -eo pipefail -c "grep -Fq 'быстрые ссылки: \${links_file}' ./modules/config/client_formats.sh; grep -Fq 'ссылка: см. \${links_file}' ./modules/config/client_formats.sh; grep -Fq 'как подключаться:' ./modules/config/client_formats.sh; grep -Fq 'render_clients_links_txt_from_json' ./modules/config/client_formats.sh; echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "print_client_config_box keeps border and content width identical" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    box=$(print_client_config_box "конфиг 12: yandex.cloud" "порт ipv4: 443" "транспорт: xhttp")
    top=$(printf "%s\n" "$box" | sed -n "1p")
    title=$(printf "%s\n" "$box" | sed -n "2p")
    sep=$(printf "%s\n" "$box" | sed -n "3p")
    body=$(printf "%s\n" "$box" | sed -n "4p")
    bottom=$(printf "%s\n" "$box" | tail -n 1)
    [ "${#top}" -eq "${#title}" ]
    [ "${#sep}" -eq "${#title}" ]
    [ "${#body}" -eq "${#title}" ]
    [ "${#bottom}" -eq "${#title}" ]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lifecycle cleanup handles missing cleanup_logging_processes function" {
    run bash -eo pipefail -c '
    count=$(grep -c '\''declare -F cleanup_logging_processes > /dev/null'\'' ./modules/lib/lifecycle.sh)
    [[ "$count" -ge 2 ]]
    ! grep -q '\''^[[:space:]]*cleanup_logging_processes || true$'\'' ./modules/lib/lifecycle.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "client_artifacts_missing detects absent files" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_KEYS="$tmp"
    mkdir -p "$XRAY_KEYS"
    touch "$XRAY_KEYS/keys.txt" "$XRAY_KEYS/clients.txt"
    if client_artifacts_missing; then
      echo "missing"
    else
      echo "complete"
    fi
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing"* ]]
}

@test "client_artifacts_missing returns false when all files exist" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_KEYS="$tmp"
    mkdir -p "$XRAY_KEYS"
    touch "$XRAY_KEYS/keys.txt" "$XRAY_KEYS/clients.txt" "$XRAY_KEYS/clients-links.txt" "$XRAY_KEYS/clients.json"
    if client_artifacts_missing; then
      echo "missing"
    else
      echo "complete"
    fi
  '
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "client_artifacts_inconsistent detects mismatched counts" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_KEYS="$tmp"
    cat > "$XRAY_KEYS/keys.txt" <<EOF
Private Key: p1
EOF
    cat > "$XRAY_KEYS/clients.txt" <<EOF
Config 1:
variant: recommended
vless link (ipv4): see /tmp/clients-links.txt
EOF
    cat > "$XRAY_KEYS/clients-links.txt" <<EOF
Config 1:
vless://u1@1.1.1.1:444?pbk=pk1#cfg1
EOF
    cat > "$XRAY_KEYS/clients.json" <<EOF
{"configs":[{"name":"Config 1"}]}
EOF
    if client_artifacts_inconsistent 2; then
      echo "inconsistent"
    else
      echo "consistent"
    fi
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"inconsistent"* ]]
}

@test "client_artifacts_inconsistent returns false for aligned artifacts" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_KEYS="$tmp"
    cat > "$XRAY_KEYS/keys.txt" <<EOF
Private Key: p1
Private Key: p2
EOF
    cat > "$XRAY_KEYS/clients.txt" <<EOF
Config 1:
variant: recommended
vless link (ipv4): see /tmp/clients-links.txt
Config 2:
variant: recommended
vless link (ipv4): see /tmp/clients-links.txt
EOF
    cat > "$XRAY_KEYS/clients-links.txt" <<EOF
Config 1:
vless://u1@1.1.1.1:444?pbk=pk1#cfg1
Config 2:
vless://u2@1.1.1.1:445?pbk=pk2#cfg2
EOF
    cat > "$XRAY_KEYS/clients.json" <<EOF
{"schema_version":2,"transport":"xhttp","configs":[{"name":"Config 1","recommended_variant":"recommended","variants":[{"key":"recommended"}]},{"name":"Config 2","recommended_variant":"recommended","variants":[{"key":"recommended"}]}]}
EOF
    if client_artifacts_inconsistent 2; then
      echo "inconsistent"
    else
      echo "consistent"
    fi
  '
    [ "$status" -eq 0 ]
    [ "$output" = "consistent" ]
}

@test "client_artifacts_inconsistent accepts localized section headings" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp=$(mktemp -d)
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_KEYS="$tmp"
    cat > "$XRAY_KEYS/keys.txt" <<EOF
Private Key: p1
Private Key: p2
EOF
    cat > "$XRAY_KEYS/clients.txt" <<EOF
конфиг 1:
- вариант: основная (recommended)
конфиг 2:
- вариант: основная (recommended)
EOF
    cat > "$XRAY_KEYS/clients-links.txt" <<EOF
конфиг 1:
основная ссылка:
vless://u1@1.1.1.1:444?pbk=pk1#cfg1
конфиг 2:
основная ссылка:
vless://u2@1.1.1.1:445?pbk=pk2#cfg2
EOF
    cat > "$XRAY_KEYS/clients.json" <<EOF
{"schema_version":3,"transport":"xhttp","configs":[{"name":"Config 1","recommended_variant":"recommended","variants":[{"key":"recommended"}]},{"name":"Config 2","recommended_variant":"recommended","variants":[{"key":"recommended"}]}]}
EOF
    if client_artifacts_inconsistent 2; then
      echo "inconsistent"
    else
      echo "consistent"
    fi
  '
    [ "$status" -eq 0 ]
    [ "$output" = "consistent" ]
}

@test "add_clients_flow always rebuilds artifacts after finalize" {
    run bash -eo pipefail -c '
    grep -q '\''rebuild_client_artifacts_from_config || {'\'' ./modules/config/add_clients.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "save_client_configs renders clients.txt from clients.json source" {
    run bash -eo pipefail -c '
    grep -q '\''save_client_configs_stage_inventory_outputs() {'\'' ./modules/config/client_formats.sh
    grep -q '\''render_clients_txt_from_json "\$json_stage" "\$client_stage"'\'' ./modules/config/client_formats.sh
    grep -q '\''save_client_configs_publish_staged_outputs() {'\'' ./modules/config/client_formats.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "client_artifacts_restore_target rejects unknown manifest state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    target="$tmp/clients.json"
    backup_root="$tmp/backup"
    mkdir -p "$backup_root"
    printf "original\n" > "$target"
    printf "clients.json=corrupted\n" > "$backup_root/manifest.env"
    if client_artifacts_restore_target "$target" "$backup_root" "clients.json"; then
      echo "unexpected-success"
    else
      echo "rejected"
    fi
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Некорректное состояние client artifact backup manifest"* ]]
    [[ "$output" == *"rejected"* ]]
}

@test "render_clients_links_txt_from_json writes russian quick-link headings" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    backup_file() { :; }
    XRAY_KEYS="$(mktemp -d)"
    trap "rm -rf \"$XRAY_KEYS\"" EXIT
    XRAY_GROUP=xray
    json_file="$XRAY_KEYS/clients.json"
    links_file="$XRAY_KEYS/clients-links.txt"
    cat > "$json_file" <<JSON
{
  "generated": "2026-03-09T01:00:00Z",
  "server_ipv4": "127.0.0.1",
  "server_ipv6": "::1",
  "configs": [
    {
      "name": "Config 1",
      "domain": "mail.ru",
      "port_ipv4": 25040,
      "recommended_variant": "recommended",
      "variants": [
        { "key": "recommended", "mode": "auto", "vless_v4": "vless://main" },
        { "key": "rescue", "mode": "packet-up", "vless_v4": "vless://rescue" },
        { "key": "emergency", "mode": "stream-up", "xray_client_file_v4": "/tmp/emergency.json", "requires": { "browser_dialer": true } }
      ]
    }
  ]
}
JSON
    render_clients_links_txt_from_json "$json_file" "$links_file"
    grep -Fq "что здесь делать:" "$links_file"
    grep -Fq "основная ссылка:" "$links_file"
    grep -Fq "запасная ссылка:" "$links_file"
    grep -Fq "аварийный raw xray:" "$links_file"
    grep -Fq "только raw xray json + browser dialer" "$links_file"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "config and client-artifact layers source dedicated modules" {
    run bash -eo pipefail -c '
    grep -Fq '\''CONFIG_RUNTIME_CONTRACT_MODULE="$SCRIPT_DIR/modules/config/runtime_contract.sh"'\'' ./config.sh
    grep -Fq '\''source "$CONFIG_RUNTIME_CONTRACT_MODULE"'\'' ./config.sh
    grep -Fq '\''CONFIG_RUNTIME_APPLY_MODULE="$SCRIPT_DIR/modules/config/runtime_apply.sh"'\'' ./config.sh
    grep -Fq '\''source "$CONFIG_RUNTIME_APPLY_MODULE"'\'' ./config.sh
    grep -Fq '\''CONFIG_CLIENT_ARTIFACTS_MODULE="$SCRIPT_DIR/modules/config/client_artifacts.sh"'\'' ./config.sh
    grep -Fq '\''source "$CONFIG_CLIENT_ARTIFACTS_MODULE"'\'' ./config.sh
    grep -Fq '\''CONFIG_CLIENT_FORMATS_MODULE="${CLIENT_ARTIFACTS_DIR}/client_formats.sh"'\'' ./modules/config/client_artifacts.sh
    grep -Fq '\''source "$CONFIG_CLIENT_FORMATS_MODULE"'\'' ./modules/config/client_artifacts.sh
    grep -Fq '\''CONFIG_CLIENT_STATE_MODULE="${CLIENT_ARTIFACTS_DIR}/client_state.sh"'\'' ./modules/config/client_artifacts.sh
    grep -Fq '\''source "$CONFIG_CLIENT_STATE_MODULE"'\'' ./modules/config/client_artifacts.sh
    grep -q '\''generate_inbound_json() {'\'' ./modules/config/runtime_contract.sh
    grep -q '\''save_environment() {'\'' ./modules/config/runtime_apply.sh
    grep -q '\''save_client_configs() {'\'' ./modules/config/client_formats.sh
    grep -q '\''rebuild_client_artifacts_from_config() {'\'' ./modules/config/client_state.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "domain planner sources dedicated runtime profiles module" {
    run bash -eo pipefail -c '
    grep -Fq '\''CONFIG_RUNTIME_PROFILES_MODULE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/runtime_profiles.sh"'\'' ./modules/config/domain_planner.sh
    grep -Fq '\''source "$CONFIG_RUNTIME_PROFILES_MODULE"'\'' ./modules/config/domain_planner.sh
    grep -q '\''allocate_ports() {'\'' ./modules/config/runtime_profiles.sh
    grep -q '\''build_inbound_profile_for_domain_values() {'\'' ./modules/config/runtime_profiles.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "build_install_quick_start_file prints primary and fallback links" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    source ./install.sh
    XRAY_KEYS="$(mktemp -d)"
    trap "rm -rf \"$XRAY_KEYS\"" EXIT
    json_file="$XRAY_KEYS/clients.json"
    out_file="$XRAY_KEYS/quick-start.txt"
    cat > "$json_file" <<JSON
{
  "configs": [
    {
      "name": "Config 1",
      "domain": "mail.ru",
      "recommended_variant": "recommended",
      "variants": [
        { "key": "recommended", "vless_v4": "vless://main" },
        { "key": "rescue", "vless_v4": "vless://rescue" },
        { "key": "emergency", "xray_client_file_v4": "/tmp/emergency.json" }
      ]
    }
  ]
}
JSON
    build_install_quick_start_file "$json_file" "$out_file"
    grep -Fq "что делать сейчас:" "$out_file"
    grep -Fq "основная ссылка:" "$out_file"
    grep -Fq "запасная ссылка:" "$out_file"
    grep -Fq "аварийный режим:" "$out_file"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "build_install_quick_start_file labels loopback lab installs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    source ./install.sh
    XRAY_KEYS="$(mktemp -d)"
    trap "rm -rf \"$XRAY_KEYS\"" EXIT
    SERVER_IP="127.0.0.1"
    json_file="$XRAY_KEYS/clients.json"
    out_file="$XRAY_KEYS/quick-start.txt"
    cat > "$json_file" <<JSON
{
  "configs": [
    {
      "name": "Config 1",
      "domain": "mail.ru",
      "recommended_variant": "recommended",
      "variants": [
        { "key": "recommended", "vless_v4": "vless://main" },
        { "key": "rescue", "vless_v4": "vless://rescue" }
      ]
    }
  ]
}
JSON
    build_install_quick_start_file "$json_file" "$out_file"
    grep -Fq "что делать сейчас:" "$out_file"
    ! grep -Fq "режим: стенд / compat" "$out_file"
    ! grep -Fq "это не боевой install path" "$out_file"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "build_install_quick_start_file labels production installs clearly" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    source ./install.sh
    XRAY_KEYS="$(mktemp -d)"
    trap "rm -rf \"$XRAY_KEYS\"" EXIT
    SERVER_IP="203.0.113.10"
    ALLOW_NO_SYSTEMD=false
    json_file="$XRAY_KEYS/clients.json"
    out_file="$XRAY_KEYS/quick-start.txt"
    cat > "$json_file" <<JSON
{
  "configs": [
    {
      "name": "Config 1",
      "domain": "mail.ru",
      "recommended_variant": "recommended",
      "variants": [
        { "key": "recommended", "vless_v4": "vless://main" },
        { "key": "rescue", "vless_v4": "vless://rescue" }
      ]
    }
  ]
}
JSON
    build_install_quick_start_file "$json_file" "$out_file"
    grep -Fq "что делать сейчас:" "$out_file"
    ! grep -Fq "режим: боевой сервер" "$out_file"
    ! grep -Fq "режим: стенд / compat" "$out_file"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "show_install_result prints explicit runtime mode notice" {
    run bash -eo pipefail -c '
    grep -Fq "print_install_runtime_mode_notice" ./modules/install/output.sh
    grep -Fq "РЕЖИМ: СТЕНД / COMPAT" ./modules/install/output.sh
    grep -Fq "РЕЖИМ: БОЕВОЙ СЕРВЕР" ./modules/install/output.sh
    grep -Fq "show_install_result" ./install.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install sources dedicated output module" {
    run bash -eo pipefail -c '
    grep -Fq '\''INSTALL_OUTPUT_MODULE="$SCRIPT_DIR/modules/install/output.sh"'\'' ./install.sh
    grep -Fq '\''source "$INSTALL_OUTPUT_MODULE"'\'' ./install.sh
    grep -q '\''show_install_result() {'\'' ./modules/install/output.sh
    grep -q '\''print_install_links_summary() {'\'' ./modules/install/output.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install sources dedicated selection module" {
    run bash -eo pipefail -c '
    grep -Fq '\''INSTALL_SELECTION_MODULE="$SCRIPT_DIR/modules/install/selection.sh"'\'' ./install.sh
    grep -Fq '\''source "$INSTALL_SELECTION_MODULE"'\'' ./install.sh
    grep -q '\''auto_configure() {'\'' ./modules/install/selection.sh
    grep -q '\''ask_domain_profile() {'\'' ./modules/install/selection.sh
    grep -q '\''ask_num_configs() {'\'' ./modules/install/selection.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install sources dedicated xray runtime module" {
    run bash -eo pipefail -c '
    grep -Fq '\''INSTALL_XRAY_RUNTIME_MODULE="$SCRIPT_DIR/modules/install/xray_runtime.sh"'\'' ./install.sh
    grep -Fq '\''source "$INSTALL_XRAY_RUNTIME_MODULE"'\'' ./install.sh
    grep -q '\''confirm_minisign_fallback() {'\'' ./modules/install/xray_runtime.sh
    grep -q '\''install_minisign() {'\'' ./modules/install/xray_runtime.sh
    grep -q '\''install_xray() {'\'' ./modules/install/xray_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "create_users avoids useradd home warning by skipping implicit home creation" {
    run bash -eo pipefail -c '
    grep -Fq "useradd -r -g \"\$XRAY_GROUP\" -s /usr/sbin/nologin -d \"\$XRAY_HOME\" -M \"\$XRAY_USER\"" ./install.sh
    ! grep -Fq "useradd -r -g \"\$XRAY_GROUP\" -s /usr/sbin/nologin -d \"\$XRAY_HOME\" -m \"\$XRAY_USER\"" ./install.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "create_users precreates writable xray log files" {
    run bash -eo pipefail -c '
    grep -Fq "declare -F ensure_xray_runtime_logs_ready" ./install.sh
    grep -Fq "ensure_xray_runtime_logs_ready" ./install.sh
    grep -Fq "touch \"\$XRAY_LOGS/access.log\" \"\$XRAY_LOGS/error.log\"" ./install.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "save_client_configs writes schema v3 strongest-direct variants when ipv6 is disabled" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh

    chown() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      if [[ -n "$mode" ]]; then
        chmod "$mode" "$target"
      fi
    }

    XRAY_KEYS="$(mktemp -d)"
    trap "rm -rf \"$XRAY_KEYS\"" EXIT

    XRAY_GROUP="xray"
    SERVER_IP="1.1.1.1"
    SERVER_IP6=""
    HAS_IPV6=false
    TRANSPORT="xhttp"
    SPIDER_MODE=false
    MUX_ENABLED=false
    MUX_CONCURRENCY=0
    QR_ENABLED=false

    NUM_CONFIGS=2
    PORTS=(443 444)
    PORTS_V6=()
    UUIDS=(u1 u2)
    SHORT_IDS=(s1 s2)
    PRIVATE_KEYS=(priv1 priv2)
    PUBLIC_KEYS=(pub1 pub2)
    CONFIG_DOMAINS=(example.com example.org)
    CONFIG_SNIS=(example.com example.org)
    CONFIG_FPS=(chrome firefox)
    CONFIG_TRANSPORT_ENDPOINTS=(/edge/api/one /edge/api/two)
    CONFIG_DESTS=(example.com:443 example.org:443)

    save_client_configs

    count=$(jq -r ".configs | length" "$XRAY_KEYS/clients.json")
    [[ "$count" == "2" ]]
    jq -e ".schema_version == 3" "$XRAY_KEYS/clients.json" > /dev/null
    jq -e ".configs[] | .variants | select(type == \"array\" and length == 3)" "$XRAY_KEYS/clients.json" > /dev/null
    jq -e ".configs[] | .recommended_variant | select(. == \"recommended\")" "$XRAY_KEYS/clients.json" > /dev/null
    jq -e ".configs[] | .variants[] | select(.key == \"emergency\") | .requires.browser_dialer == true" "$XRAY_KEYS/clients.json" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_existing_vless_encryptions_from_artifacts keeps in-memory values when legacy artifacts are stale" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp_dir=$(mktemp -d)
    trap "rm -rf \"$tmp_dir\"" EXIT
    XRAY_KEYS="$tmp_dir"
    CONFIG_DOMAINS=(market.yandex.ru snob.ru)
    CONFIG_VLESS_ENCRYPTIONS=(enc-alpha enc-beta)
    cat > "$tmp_dir/clients.json" <<JSON
{
  "schema_version": 3,
  "transport": "xhttp",
  "configs": [
    { "domain": "market.yandex.ru", "vless_encryption": "none", "recommended_variant": "recommended", "variants": [] },
    { "domain": "snob.ru", "vless_encryption": "none", "recommended_variant": "recommended", "variants": [] }
  ]
}
JSON
    load_existing_vless_encryptions_from_artifacts
    [[ "${CONFIG_VLESS_ENCRYPTIONS[0]}" == "enc-alpha" ]]
    [[ "${CONFIG_VLESS_ENCRYPTIONS[1]}" == "enc-beta" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "add_clients_flow rebuilds artifacts from config after append" {
    run bash -eo pipefail -c '
    grep -q '\''rebuild_client_artifacts_from_config || {'\'' ./modules/config/add_clients.sh
    grep -q '\''print_add_clients_result "\$add_count" "\$client_file"'\'' ./modules/config/add_clients.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rebuild_client_artifacts_from_config rebuilds via stubs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    load_existing_ports_from_config() { PORTS=(444); PORTS_V6=(); HAS_IPV6=false; }
    load_existing_metadata_from_config() { CONFIG_DOMAINS=(yandex.ru); CONFIG_SNIS=(yandex.ru); CONFIG_FPS=(chrome); CONFIG_TRANSPORT_ENDPOINTS=(/edge/api/demo); CONFIG_DESTS=(yandex.ru:443); TRANSPORT=xhttp; }
    load_keys_from_config() { UUIDS=(u1); SHORT_IDS=(abcd1234); PRIVATE_KEYS=(priv1); }
    build_public_keys_for_current_config() { PUBLIC_KEYS=(pub1); return 0; }
    save_client_configs() { echo "saved"; return 0; }
    export_all_configs() { echo "exported"; return 0; }
    XRAY_KEYS="$(mktemp -d)"
    SERVER_IP="127.0.0.1"
    SERVER_IP6=""
    TRANSPORT="xhttp"
    SPIDER_MODE=true
    MUX_ENABLED=false
    MUX_CONCURRENCY=0
    XRAY_GROUP="xray"
    if rebuild_client_artifacts_from_config; then
      echo "ok"
    else
      echo "fail"
      exit 1
    fi
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"saved"* ]]
    [[ "$output" == *"exported"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "rebuild_config_for_transport rebuilds xhttp config and refreshes runtime metadata" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    TMPDIR="$tmp"
    XRAY_CONFIG="$tmp/config.json"
    log() { :; }
    check_xray_version_for_config_generation() { :; }
    ensure_xray_feature_contract() { :; }
    setup_mux_settings() { :; }
    detect_reality_dest() { printf "443\n"; }
    domain_provider_family_for() { printf "tier-test\n"; }
    generate_xhttp_path_for_domain() { printf "/edge/api/rebuilt\n"; }
    generate_vless_encryption_pair() { printf "decrypt-A\tencrypt-A\n"; }
    rand_between() { printf "10\n"; }
    generate_inbound_json() {
      MSYS_NO_PATHCONV=1 jq -nc --arg transport "${12}" --arg dest "$3" --arg endpoint "$8" --arg payload "${13}" --arg decrypt "${14}" \
        "{transport:\$transport,dest:\$dest,endpoint:\$endpoint,payload:\$payload,vless_decryption:\$decrypt}"
    }
    generate_outbounds_json() { printf "[]\n"; }
    generate_routing_json() { printf "{}\n"; }
    backup_file() { :; }
    set_temp_xray_config_permissions() { :; }
    apply_validated_config() { mv "$1" "$XRAY_CONFIG"; }

    NUM_CONFIGS=1
    HAS_IPV6=false
    TRANSPORT="grpc"
    PORTS=(24443)
    PORTS_V6=()
    UUIDS=("uuid-1")
    SHORT_IDS=("abcd1234")
    PRIVATE_KEYS=("private-1")
    CONFIG_DOMAINS=("example.com")
    CONFIG_SNIS=("")
    CONFIG_FPS=("chrome")
    CONFIG_TRANSPORT_ENDPOINTS=("legacy-endpoint")
    CONFIG_DESTS=("")
    CONFIG_PROVIDER_FAMILIES=("")
    CONFIG_VLESS_ENCRYPTIONS=("none")
    CONFIG_VLESS_DECRYPTIONS=("none")

    rebuild_config_for_transport xhttp

    [[ "$TRANSPORT" == "xhttp" ]]
    [[ "${CONFIG_DESTS[0]}" == "example.com:443" ]]
    [[ "${CONFIG_TRANSPORT_ENDPOINTS[0]}" == "/edge/api/rebuilt" ]]
    [[ "${CONFIG_PROVIDER_FAMILIES[0]}" == "tier-test" ]]
    [[ "${CONFIG_VLESS_DECRYPTIONS[0]}" == "decrypt-A" ]]
    [[ "${CONFIG_VLESS_ENCRYPTIONS[0]}" == "encrypt-A" ]]
    jq -e ".inbounds[0].transport == \"xhttp\"" "$XRAY_CONFIG" > /dev/null
    jq -e ".inbounds[0].dest == \"example.com:443\"" "$XRAY_CONFIG" > /dev/null
    jq -e ".inbounds[0].payload == \"/edge/api/rebuilt\"" "$XRAY_CONFIG" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "reorder_runtime_arrays_to_primary_index skips empty optional arrays" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    PORTS=(1001 1002)
    PORTS_V6=()
    UUIDS=(u1 u2)
    SHORT_IDS=(s1 s2)
    PRIVATE_KEYS=(k1 k2)
    PUBLIC_KEYS=(p1 p2)
    CONFIG_DOMAINS=(d1 d2)
    CONFIG_DESTS=(dst1 dst2)
    CONFIG_SNIS=(sn1 sn2)
    CONFIG_FPS=(fp1 fp2)
    CONFIG_TRANSPORT_ENDPOINTS=(ep1 ep2)
    CONFIG_PROVIDER_FAMILIES=(pf1 pf2)
    CONFIG_VLESS_ENCRYPTIONS=(ve1 ve2)
    CONFIG_VLESS_DECRYPTIONS=(vd1 vd2)
    reorder_runtime_arrays_to_primary_index 1
    [[ "${PORTS[0]}" == "1002" ]]
    [[ "${UUIDS[0]}" == "u2" ]]
    [[ "${CONFIG_DOMAINS[0]}" == "d2" ]]
    [[ ${#PORTS_V6[@]} -eq 0 ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "repair_flow fails closed when client artifacts rebuild degrades" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    printf "{}\n" > "$XRAY_CONFIG"
    XRAY_KEYS="$tmp/keys"
    mkdir -p "$XRAY_KEYS"
    XRAY_BIN="$tmp/xray"
    printf "#!/usr/bin/env bash\nexit 0\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    LOG_CONTEXT=""
    INSTALL_LOG="$tmp/repair.log"
    setup_logging() { :; }
    resolve_paths() { :; }
    detect_distro() { :; }
    install_dependencies() { :; }
    require_cmd() { :; }
    install_self() { :; }
    setup_logrotate() { :; }
    create_users() { :; }
    install_minisign() { :; }
    xray_config_test_ok() { return 0; }
    create_systemd_service() { :; }
    setup_diagnose_service() { :; }
    load_existing_ports_from_config() { PORTS=(24443); PORTS_V6=(); }
    load_existing_metadata_from_config() {
      CONFIG_DOMAINS=(example.com); CONFIG_SNIS=(example.com); CONFIG_FPS=(chrome)
      CONFIG_TRANSPORT_ENDPOINTS=(/edge/api/test); CONFIG_DESTS=(example.com:443)
      CONFIG_PROVIDER_FAMILIES=(tier-test); CONFIG_VLESS_ENCRYPTIONS=(enc); CONFIG_VLESS_DECRYPTIONS=(dec)
      TRANSPORT=xhttp
    }
    load_keys_from_config() { UUIDS=(u1); SHORT_IDS=(s1); PRIVATE_KEYS=(k1); PUBLIC_KEYS=(p1); }
    build_public_keys_for_current_config() { return 0; }
    maybe_promote_runtime_primary_from_observations() { return 0; }
    configure_firewall() { :; }
    setup_health_monitoring() { :; }
    setup_auto_update() { :; }
    start_services() { :; }
    verify_ports_listening_after_start() { return 0; }
    test_reality_connectivity() { return 0; }
    fetch_ip() { printf "127.0.0.1\n"; }
    save_environment() { :; }
    save_policy_file() { :; }
    rebuild_client_artifacts_from_loaded_state() { return 1; }
    ensure_self_check_artifacts_ready() { return 0; }
    post_action_verdict() { echo "unexpected-post-action"; return 0; }
    log() { printf "%s %s\n" "$1" "$2"; }
    repair_flow
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Не удалось полностью восстановить клиентские артефакты"* ]]
    [[ "$output" == *"Восстановление завершилось с деградированными клиентскими или self-check артефактами"* ]]
    [[ "$output" != *"unexpected-post-action"* ]]
}

@test "repair_flow fails closed when self-check artifacts degrade" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    printf "{}\n" > "$XRAY_CONFIG"
    XRAY_KEYS="$tmp/keys"
    mkdir -p "$XRAY_KEYS"
    XRAY_BIN="$tmp/xray"
    printf "#!/usr/bin/env bash\nexit 0\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    LOG_CONTEXT=""
    INSTALL_LOG="$tmp/repair.log"
    setup_logging() { :; }
    resolve_paths() { :; }
    detect_distro() { :; }
    install_dependencies() { :; }
    require_cmd() { :; }
    install_self() { :; }
    setup_logrotate() { :; }
    create_users() { :; }
    install_minisign() { :; }
    xray_config_test_ok() { return 0; }
    create_systemd_service() { :; }
    setup_diagnose_service() { :; }
    load_existing_ports_from_config() { PORTS=(24443); PORTS_V6=(); }
    load_existing_metadata_from_config() {
      CONFIG_DOMAINS=(example.com); CONFIG_SNIS=(example.com); CONFIG_FPS=(chrome)
      CONFIG_TRANSPORT_ENDPOINTS=(/edge/api/test); CONFIG_DESTS=(example.com:443)
      CONFIG_PROVIDER_FAMILIES=(tier-test); CONFIG_VLESS_ENCRYPTIONS=(enc); CONFIG_VLESS_DECRYPTIONS=(dec)
      TRANSPORT=xhttp
    }
    load_keys_from_config() { UUIDS=(u1); SHORT_IDS=(s1); PRIVATE_KEYS=(k1); PUBLIC_KEYS=(p1); }
    build_public_keys_for_current_config() { return 0; }
    maybe_promote_runtime_primary_from_observations() { return 0; }
    configure_firewall() { :; }
    setup_health_monitoring() { :; }
    setup_auto_update() { :; }
    start_services() { :; }
    verify_ports_listening_after_start() { return 0; }
    test_reality_connectivity() { return 0; }
    fetch_ip() { printf "127.0.0.1\n"; }
    save_environment() { :; }
    save_policy_file() { :; }
    rebuild_client_artifacts_from_loaded_state() { return 0; }
    ensure_self_check_artifacts_ready() { return 1; }
    post_action_verdict() { echo "unexpected-post-action"; return 0; }
    log() { printf "%s %s\n" "$1" "$2"; }
    repair_flow
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Не удалось полностью подготовить self-check артефакты"* ]]
    [[ "$output" == *"Восстановление завершилось с деградированными клиентскими или self-check артефактами"* ]]
    [[ "$output" != *"unexpected-post-action"* ]]
}

@test "export helpers clean temp files when jq parsing fails" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./export.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    bad_json="$tmp/bad.json"
    printf "{broken\n" > "$bad_json"
    out1="$tmp/raw-index.json"
    out2="$tmp/v2rayn.json"
    out3="$tmp/nekoray.json"
    log() { :; }
    ! export_raw_xray_index "$bad_json" "$out1"
    ! export_v2rayn_fragment_template "$bad_json" "$out2"
    ! export_nekoray_fragment_template "$bad_json" "$out3"
    compgen -G "$tmp/*.tmp.*" > /dev/null && exit 1
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "rebuild_config_for_transport fails closed when config domain is missing" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    log() { :; }
    check_xray_version_for_config_generation() { :; }
    ensure_xray_feature_contract() { :; }
    setup_mux_settings() { :; }

    printf "{\"old\":true}\n" > "$XRAY_CONFIG"
    NUM_CONFIGS=1
    HAS_IPV6=false
    TRANSPORT="grpc"
    PORTS=(24443)
    PORTS_V6=()
    UUIDS=("uuid-1")
    SHORT_IDS=("abcd1234")
    PRIVATE_KEYS=("private-1")
    CONFIG_DOMAINS=("")
    CONFIG_SNIS=("legacy-sni")
    CONFIG_FPS=("chrome")
    CONFIG_TRANSPORT_ENDPOINTS=("legacy-endpoint")
    CONFIG_DESTS=("legacy-dest")
    CONFIG_PROVIDER_FAMILIES=("legacy-family")
    CONFIG_VLESS_ENCRYPTIONS=("legacy-encryption")
    CONFIG_VLESS_DECRYPTIONS=("legacy-decryption")

    if rebuild_config_for_transport xhttp; then
      echo "unexpected-success"
      exit 1
    fi

    [[ "$TRANSPORT" == "grpc" ]]
    [[ "${CONFIG_DESTS[0]}" == "legacy-dest" ]]
    jq -e ".old == true" "$XRAY_CONFIG" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "rebuild_config_for_transport skips grpc timeout randomization for xhttp" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp/config.json"
    calls="$tmp/rand-calls.log"
    log() { :; }
    check_xray_version_for_config_generation() { :; }
    ensure_xray_feature_contract() { :; }
    setup_mux_settings() { :; }
    detect_reality_dest() { printf "443\n"; }
    domain_provider_family_for() { printf "tier-test\n"; }
    generate_xhttp_path_for_domain() { printf "/edge/api/rebuilt\n"; }
    generate_vless_encryption_pair() { printf "decrypt-A\tencrypt-A\n"; }
    rand_between() {
      printf "%s:%s\n" "$1" "$2" >> "$calls"
      printf "10\n"
    }
    generate_inbound_json() {
      MSYS_NO_PATHCONV=1 jq -nc --arg transport "${12}" --arg grpc_idle "${10}" --arg grpc_health "${11}" \
        "{transport:\$transport,grpc_idle:(\$grpc_idle|tonumber),grpc_health:(\$grpc_health|tonumber)}"
    }
    generate_outbounds_json() { printf "[]\n"; }
    generate_routing_json() { printf "{}\n"; }
    backup_file() { :; }
    set_temp_xray_config_permissions() { :; }
    apply_validated_config() { mv "$1" "$XRAY_CONFIG"; }

    TCP_KEEPALIVE_MIN=20
    TCP_KEEPALIVE_MAX=21
    GRPC_IDLE_TIMEOUT_MIN=600
    GRPC_IDLE_TIMEOUT_MAX=601
    GRPC_HEALTH_TIMEOUT_MIN=700
    GRPC_HEALTH_TIMEOUT_MAX=701
    NUM_CONFIGS=1
    HAS_IPV6=false
    TRANSPORT="grpc"
    PORTS=(24443)
    PORTS_V6=()
    UUIDS=("uuid-1")
    SHORT_IDS=("abcd1234")
    PRIVATE_KEYS=("private-1")
    CONFIG_DOMAINS=("example.com")
    CONFIG_SNIS=("")
    CONFIG_FPS=("chrome")
    CONFIG_TRANSPORT_ENDPOINTS=("legacy-endpoint")
    CONFIG_DESTS=("")
    CONFIG_PROVIDER_FAMILIES=("")
    CONFIG_VLESS_ENCRYPTIONS=("none")
    CONFIG_VLESS_DECRYPTIONS=("none")

    rebuild_config_for_transport xhttp

    grep -Fxq "20:21" "$calls"
    ! grep -Fq "600:601" "$calls"
    ! grep -Fq "700:701" "$calls"
    jq -e ".inbounds[0].grpc_idle == 0" "$XRAY_CONFIG" > /dev/null
    jq -e ".inbounds[0].grpc_health == 0" "$XRAY_CONFIG" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "config root json writer is shared by build and rebuild paths" {
    run bash -eo pipefail -c '
    grep -q "^write_xray_root_config_json()" ./config.sh
    count=$(grep -c '\''write_xray_root_config_json "\$inbounds" "\$outbounds" "\$routing" > "\$tmp_config"'\'' ./config.sh)
    [[ "$count" -eq 2 ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "load_existing_* supports explicit ipv4 listen and filters non-reality inbounds" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 444,
      "settings": {"clients": [{"id": "uuid-v4"}]},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "svc.v4"},
        "realitySettings": {
          "dest": "yandex.ru:443",
          "serverNames": ["music.yandex.ru"],
          "fingerprint": "chrome",
          "shortIds": ["abcd1234"],
          "privateKey": "priv-v4"
        }
      }
    },
    {
      "listen": "::1",
      "port": 445,
      "settings": {"clients": [{"id": "uuid-v6"}]},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "svc.v6"},
        "realitySettings": {
          "dest": "vk.com:443",
          "serverNames": ["vk.com"],
          "fingerprint": "firefox",
          "shortIds": ["efgh5678"],
          "privateKey": "priv-v6"
        }
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 1080,
      "settings": {},
      "streamSettings": {"network": "tcp"}
    }
  ]
}
EOF
    XRAY_CONFIG="$tmp"
    load_existing_ports_from_config
    load_existing_metadata_from_config
    load_keys_from_config
    echo "PORTS=${PORTS[*]}"
    echo "PORTS_V6=${PORTS_V6[*]}"
    echo "UUIDS=${UUIDS[*]}"
    echo "DOMAINS=${CONFIG_DOMAINS[*]}"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"PORTS=444"* ]]
    [[ "$output" == *"PORTS_V6=445"* ]]
    [[ "$output" == *"UUIDS=uuid-v4"* ]]
    [[ "$output" == *"DOMAINS=yandex.ru"* ]]
}

@test "save_environment escapes command substitution and keeps 0600 mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }

    rm -f /tmp/xray_env_injection_test
    tmp_env=$(mktemp)
    tmp_bin_dir=$(mktemp -d)
    trap "rm -f \"$tmp_env\" /tmp/xray_env_injection_test; rm -rf \"$tmp_bin_dir\"" EXIT

    cat > "${tmp_bin_dir}/xray" <<EOF
#!/usr/bin/env bash
echo "Xray 1.8.0"
EOF
    chmod +x "${tmp_bin_dir}/xray"

    XRAY_BIN="${tmp_bin_dir}/xray"
    XRAY_ENV="$tmp_env"
    SERVER_IP='\''1.2.3.4$(touch /tmp/xray_env_injection_test)'\''
    SERVER_IP6=""
    SPIDER_MODE="false"

    save_environment
    grep -q '\''atomic_write "\$XRAY_ENV" 0600'\'' ./modules/config/runtime_apply.sh
    source "$XRAY_ENV"

    [[ ! -e /tmp/xray_env_injection_test ]]
    [[ "$SERVER_IP" == '\''1.2.3.4$(touch /tmp/xray_env_injection_test)'\'' ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "save_environment writes legacy aliases for env compatibility" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }

    tmp_env=$(mktemp)
    tmp_bin_dir=$(mktemp -d)
    trap "rm -f \"$tmp_env\"; rm -rf \"$tmp_bin_dir\"" EXIT

    cat > "${tmp_bin_dir}/xray" <<EOF
#!/usr/bin/env bash
echo "Xray 1.8.0"
EOF
    chmod +x "${tmp_bin_dir}/xray"

    XRAY_BIN="${tmp_bin_dir}/xray"
    XRAY_ENV="$tmp_env"
    DOMAIN_TIER="tier_global_ms10"
    NUM_CONFIGS=3
    START_PORT=24440
    SPIDER_MODE="true"
    TRANSPORT="xhttp"
    PROGRESS_MODE="plain"
    SERVER_IP="127.0.0.1"
    SERVER_IP6="::1"

    save_environment
    grep -q "^DOMAIN_TIER=" "$XRAY_ENV"
    grep -q "^XRAY_DOMAIN_TIER=" "$XRAY_ENV"
    grep -q "^NUM_CONFIGS=" "$XRAY_ENV"
    grep -q "^XRAY_NUM_CONFIGS=" "$XRAY_ENV"
    grep -q "^START_PORT=" "$XRAY_ENV"
    grep -q "^XRAY_START_PORT=" "$XRAY_ENV"
    grep -q "^SPIDER_MODE=" "$XRAY_ENV"
    grep -q "^XRAY_SPIDER_MODE=" "$XRAY_ENV"
    grep -q "^PROGRESS_MODE=" "$XRAY_ENV"
    grep -q "^XRAY_PROGRESS_MODE=" "$XRAY_ENV"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "save_environment persists inline custom domains into managed state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      mkdir -p "$(dirname "$target")"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }

    tmp_env=$(mktemp)
    tmp_dir=$(mktemp -d)
    tmp_bin_dir=$(mktemp -d)
    trap "rm -f \"$tmp_env\"; rm -rf \"$tmp_dir\" \"$tmp_bin_dir\"" EXIT

    cat > "${tmp_bin_dir}/xray" <<EOF
#!/usr/bin/env bash
echo "Xray 1.8.0"
EOF
    chmod +x "${tmp_bin_dir}/xray"

    XRAY_BIN="${tmp_bin_dir}/xray"
    XRAY_ENV="$tmp_env"
    XRAY_MANAGED_CUSTOM_DOMAINS_FILE="${tmp_dir}/custom-domains.txt"
    XRAY_CUSTOM_DOMAINS="vk.com, yoomoney.ru ,cdek.ru"
    XRAY_DOMAINS_FILE=""
    DOMAIN_TIER="custom"
    DOMAIN_PROFILE="custom"
    SERVER_IP="127.0.0.1"
    SERVER_IP6=""
    SPIDER_MODE="true"

    save_environment

    ! grep -q "^XRAY_CUSTOM_DOMAINS=" "$XRAY_ENV"
    grep -q "^XRAY_DOMAINS_FILE=" "$XRAY_ENV"
    grep -Fxq "vk.com" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"
    grep -Fxq "yoomoney.ru" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"
    grep -Fxq "cdek.ru" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"

    XRAY_DOMAINS_FILE=""
    XRAY_CUSTOM_DOMAINS=""
    load_config_file "$XRAY_ENV"
    [[ "$XRAY_DOMAINS_FILE" == "${tmp_dir}/custom-domains.txt" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "save_environment copies XRAY_DOMAINS_FILE into managed custom state" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    backup_file() { :; }
    atomic_write() {
      local target="$1"
      local mode="${2:-}"
      mkdir -p "$(dirname "$target")"
      cat > "$target"
      [[ -n "$mode" ]] && chmod "$mode" "$target"
    }

    tmp_env=$(mktemp)
    tmp_dir=$(mktemp -d)
    tmp_bin_dir=$(mktemp -d)
    tmp_source=$(mktemp)
    trap "rm -f \"$tmp_env\" \"$tmp_source\"; rm -rf \"$tmp_dir\" \"$tmp_bin_dir\"" EXIT

    cat > "${tmp_bin_dir}/xray" <<EOF
#!/usr/bin/env bash
echo "Xray 1.8.0"
EOF
    chmod +x "${tmp_bin_dir}/xray"
    cat > "$tmp_source" <<EOF
# comment
vk.com
yoomoney.ru
EOF

    XRAY_BIN="${tmp_bin_dir}/xray"
    XRAY_ENV="$tmp_env"
    XRAY_MANAGED_CUSTOM_DOMAINS_FILE="${tmp_dir}/custom-domains.txt"
    XRAY_CUSTOM_DOMAINS=""
    XRAY_DOMAINS_FILE="$tmp_source"
    DOMAIN_TIER="custom"
    DOMAIN_PROFILE="custom"
    SERVER_IP="127.0.0.1"
    SERVER_IP6=""
    SPIDER_MODE="true"

    save_environment
    rm -f "$tmp_source"

    grep -Fxq "vk.com" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"
    grep -Fxq "yoomoney.ru" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"
    ! grep -q "^# comment$" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"
    XRAY_DOMAINS_FILE=""
    load_config_file "$XRAY_ENV"
    [[ "$XRAY_DOMAINS_FILE" == "${tmp_dir}/custom-domains.txt" ]]
    echo ok
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_config_file keeps legacy key compatibility" {
    run bash -eo pipefail -c '
    source ./lib.sh

    cfg=$(mktemp)
    trap "rm -f \"$cfg\"" EXIT
    cat > "$cfg" <<EOF
DOMAIN_TIER=tier_global_ms10
NUM_CONFIGS="4"
SPIDER_MODE=true
START_PORT=25555
HEALTH_LOG="/var/log/xray/custom-health.log"
GH_PROXY_BASE="https://ghproxy.com/https://github.com"
PROGRESS_MODE=plain
UNKNOWN_KEY=ignored
EOF

    DOMAIN_TIER=tier_ru
    NUM_CONFIGS=1
    SPIDER_MODE=false
    START_PORT=443
    HEALTH_LOG=""
    GH_PROXY_BASE=""
    PROGRESS_MODE="auto"

    load_config_file "$cfg"
    [[ "$DOMAIN_TIER" == "tier_global_ms10" ]]
    [[ "$NUM_CONFIGS" == "4" ]]
    [[ "$SPIDER_MODE" == "true" ]]
    [[ "$START_PORT" == "25555" ]]
    [[ "$HEALTH_LOG" == "/var/log/xray/custom-health.log" ]]
    [[ "$GH_PROXY_BASE" == "https://ghproxy.com/https://github.com" ]]
    [[ "$PROGRESS_MODE" == "plain" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_config_file strips matching single quotes" {
    run bash -eo pipefail -c "
    source ./lib.sh

    cfg=\$(mktemp)
    trap 'rm -f \"\$cfg\"' EXIT
    cat > \"\$cfg\" <<'EOF'
PRIMARY_PIN_DOMAIN='example.com'
HEALTH_LOG='/var/log/xray/custom-health.log'
EOF

    PRIMARY_PIN_DOMAIN=''
    HEALTH_LOG=''

    load_config_file \"\$cfg\"
    [[ \"\$PRIMARY_PIN_DOMAIN\" == 'example.com' ]]
    [[ \"\$HEALTH_LOG\" == '/var/log/xray/custom-health.log' ]]
    echo ok
  "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_runtime_identity_defaults backfills managed runtime identity without overriding explicit values" {
    run bash -eo pipefail -c "
    source ./lib.sh

    cfg=\$(mktemp)
    trap 'rm -f \"\$cfg\"' EXIT
    cat > \"\$cfg\" <<'EOF'
SERVER_IP=10.0.2.15
SERVER_IP6=2001:db8::15
DOMAIN_TIER=tier_ru
XRAY_DOMAIN_PROFILE=ru-auto
START_PORT=24440
NUM_CONFIGS=2
SPIDER_MODE=true
EOF

    SERVER_IP=''
    SERVER_IP6=''
    DOMAIN_TIER=''
    DOMAIN_PROFILE=''
    START_PORT=''
    NUM_CONFIGS=''
    SPIDER_MODE=''
    load_runtime_identity_defaults \"\$cfg\"
    [[ \"\$SERVER_IP\" == '10.0.2.15' ]]
    [[ \"\$SERVER_IP6\" == '2001:db8::15' ]]
    [[ \"\$DOMAIN_TIER\" == 'tier_ru' ]]
    [[ \"\$DOMAIN_PROFILE\" == 'ru-auto' ]]
    [[ \"\$START_PORT\" == '24440' ]]
    [[ \"\$NUM_CONFIGS\" == '2' ]]
    [[ \"\$SPIDER_MODE\" == 'true' ]]

    SERVER_IP='198.51.100.20'
    load_runtime_identity_defaults \"\$cfg\"
    [[ \"\$SERVER_IP\" == '198.51.100.20' ]]
    echo ok
  "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "load_runtime_identity_defaults backfills source metadata without overriding wrapper values" {
    run bash -eo pipefail -c "
    source ./lib.sh

    cfg=\$(mktemp)
    trap 'rm -f \"\$cfg\"' EXIT
    cat > \"\$cfg\" <<'EOF'
XRAY_SOURCE_KIND=bootstrap
XRAY_SOURCE_REF=v7.5.2
XRAY_SOURCE_COMMIT=2fba5138b5e629891ef92f909f163af0b1a988d9
EOF

    XRAY_SOURCE_KIND=''
    XRAY_SOURCE_REF=''
    XRAY_SOURCE_COMMIT=''
    load_runtime_identity_defaults \"\$cfg\"
    [[ \"\$XRAY_SOURCE_KIND\" == 'bootstrap' ]]
    [[ \"\$XRAY_SOURCE_REF\" == 'v7.5.2' ]]
    [[ \"\$XRAY_SOURCE_COMMIT\" == '2fba5138b5e629891ef92f909f163af0b1a988d9' ]]

    XRAY_SOURCE_COMMIT='override'
    load_runtime_identity_defaults \"\$cfg\"
    [[ \"\$XRAY_SOURCE_COMMIT\" == 'override' ]]
    echo ok
  "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "build_vless_query_params URL-encodes special characters" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    params=$(build_vless_query_params "exa&mple.com" "fire fox" "abc+123" "s#id" "xhttp" "/svc/one-x" "packet-up")
    [[ "$params" == *"sni=exa%26mple.com"* ]]
    [[ "$params" == *"fp=fire%20fox"* ]]
    [[ "$params" == *"pbk=abc%2B123"* ]]
    [[ "$params" == *"sid=s%23id"* ]]
    [[ "$params" == *"type=xhttp"* ]]
    [[ "$params" == *"path=%2Fsvc%2Fone-x"* ]]
    [[ "$params" == *"mode=packet-up"* ]]
    [[ "$params" != *"sni=exa&mple.com"* ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "generate_uuid falls back when uuidgen output is invalid" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./modules/config/domain_planner.sh
    uuidgen() { echo "broken"; return 0; }
    uuid=$(generate_uuid)
    [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
    [[ "${uuid:14:1}" == "4" ]]
    [[ "${uuid:19:1}" =~ ^[89aAbB]$ ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "service unit helpers reject unsafe systemd values" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    sanitize_systemd_value cleaned $'\''xray\r\n\t'\''
    sanitize_systemd_value_into cleaned_into $'\''xray\r\n\t'\''
    [[ "$cleaned" == "xray" ]]
    [[ "$cleaned_into" == "xray" ]]
    validate_systemd_path_value "/usr/local/bin/xray" "XRAY_BIN"
    if validate_systemd_path_value "xray;/bin/sh" "XRAY_BIN"; then
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "systemd_log_supplementary_groups derives parent traversal group for restricted log paths" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh

    tmpbin="$(mktemp -d)"
    trap "rm -rf \"$tmpbin\"" EXIT
    cat > "$tmpbin/stat" <<'\''EOF'\''
#!/usr/bin/env bash
target="${@: -1}"
case "$target" in
    /)
        printf "%s\n" "root:root:755"
        ;;
    /var)
        printf "%s\n" "root:root:755"
        ;;
    /var/log)
        printf "%s\n" "root:syslog:750"
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod 755 "$tmpbin/stat"
    PATH="$tmpbin:$PATH"

    XRAY_USER="xray"
    XRAY_GROUP="xray"
    derived="$(systemd_log_supplementary_groups "/var/log/xray" "$XRAY_USER" "$XRAY_GROUP")"
    [[ "$derived" == "syslog" ]]
    [[ "$(systemd_log_access_directives "/var/log/xray" "$XRAY_USER" "$XRAY_GROUP")" == *"SupplementaryGroups=syslog"* ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "systemd_log_supplementary_groups preserves /var/log parent group for default log path even if others can traverse" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh

    tmpbin="$(mktemp -d)"
    cat > "$tmpbin/stat" <<'\''EOF'\''
#!/usr/bin/env bash
case "$*" in
    "-c %U:%G:%a /var")
        printf '\''%s\n'\'' '\''root:root:755'\''
        ;;
    "-c %U:%G:%a /var/log")
        printf '\''%s\n'\'' '\''root:syslog:775'\''
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod 755 "$tmpbin/stat"
    PATH="$tmpbin:$PATH"

    XRAY_USER="xray"
    XRAY_GROUP="xray"
    derived="$(systemd_log_supplementary_groups "/var/log/xray" "$XRAY_USER" "$XRAY_GROUP")"
    [[ "$derived" == "syslog" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "create_systemd_service handles missing systemd dir in non-systemd mode" {
    run bash -eo pipefail -c '
    grep -q '\''local systemd_dir="/etc/systemd/system"'\'' ./modules/service/runtime.sh
    grep -q '\''install -d -m 755 "\$systemd_dir"'\'' ./modules/service/runtime.sh
    grep -q '\''создание unit-файла пропущено'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "create_systemd_service cleans conflicting xray drop-ins" {
    run bash -eo pipefail -c '
    grep -q '\''cleanup_conflicting_xray_service_dropins'\'' ./modules/service/runtime.sh
    grep -q '\''/etc/systemd/system/xray.service.d'\'' ./modules/service/runtime.sh
    grep -q '\''runtime_override_regex='\'' ./modules/service/runtime.sh
    grep -q '\''Environment(File)?'\'' ./modules/service/runtime.sh
    grep -q '\''safe-mode'\'' ./modules/service/runtime.sh
    grep -Fq -- '\''-type f -o -type l'\'' ./modules/service/runtime.sh
    grep -q '\''Отключён конфликтный systemd drop-in'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "create_systemd_service uses systemd-native log dirs and fallback writable paths" {
    run bash -eo pipefail -c '
    grep -Fq '\''ensure_xray_runtime_logs_ready || {'\'' ./modules/service/runtime.sh
    grep -Fq '\''chown "${XRAY_USER}:${XRAY_GROUP}" "$logs_dir"'\'' ./modules/service/runtime.sh
    grep -Fq '\''chmod 750 "$logs_dir"'\'' ./modules/service/runtime.sh
    grep -Fq '\''systemd_log_access_directives()'\'' ./modules/service/runtime.sh
    grep -Fq '\''systemd_log_supplementary_groups()'\'' ./modules/service/runtime.sh
    grep -Fq '\''SupplementaryGroups=%s\n'\'' ./modules/service/runtime.sh
    grep -Fq '\''LogsDirectory=xray'\'' ./modules/service/runtime.sh
    grep -Fq '\''LogsDirectoryMode=0750'\'' ./modules/service/runtime.sh
    grep -Fq '\''printf '\''"'\''ReadWritePaths=%s\n'\''"'\'' "$logs_path"'\'' ./modules/service/runtime.sh
    grep -Fq '\''UMask=0027'\'' ./modules/service/runtime.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "service systemd flows degrade on nonfatal systemctl errors" {
    run bash -eo pipefail -c '
    grep -q '\''is_nonfatal_systemctl_error()'\'' ./modules/service/runtime.sh
    grep -q '\''local daemon_reload_rc=0'\'' ./modules/service/runtime.sh
    grep -q '\''local enable_rc=0'\'' ./modules/service/runtime.sh
    grep -q '\''if ((daemon_reload_rc != 0)); then'\'' ./modules/service/runtime.sh
    grep -q '\''if ((enable_rc != 0)); then'\'' ./modules/service/runtime.sh
    grep -q '\''if ! systemctl_restart_xray_bounded restart_err; then'\'' ./modules/service/runtime.sh
    grep -q '\''SYSTEMD_MANAGEMENT_DISABLED=true'\'' ./modules/service/runtime.sh
    grep -q '\''systemd недоступен для активации unit; продолжаем без enable'\'' ./modules/service/runtime.sh
    grep -q '\''systemd недоступен для restart xray; запуск сервисов пропущен'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rollback uses bounded systemctl operations" {
    run bash -eo pipefail -c '
    grep -q '\''runtime_quiesce_for_restore'\'' ./service.sh
    grep -q '\''restore_file_from_snapshot'\'' ./service.sh
    grep -q '\''reconcile_runtime_after_restore'\'' ./service.sh
    grep -q '\''systemctl_uninstall_bounded stop xray-health.timer'\'' ./modules/lib/lifecycle.sh
    grep -q '\''systemctl_uninstall_bounded stop xray-auto-update.timer'\'' ./modules/lib/lifecycle.sh
    grep -q '\''systemctl_uninstall_bounded stop xray'\'' ./modules/lib/lifecycle.sh
    grep -q '\''mv -f "$tmp_path" "$dest_path"'\'' ./modules/lib/lifecycle.sh
    ! grep -q '\''if ! systemctl stop xray > /dev/null 2>&1; then'\'' ./service.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "health monitoring uses bounded restart and unit timeout" {
    run bash -eo pipefail -c '
    grep -q '\''restart_xray_bounded()'\'' ./health.sh
    grep -q '\''timeout --signal=TERM --kill-after=10s'\'' ./health.sh
    grep -q '\''if restart_xray_bounded; then'\'' ./health.sh
    grep -q '\''TimeoutStartSec=90s'\'' ./health.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "require_systemd_runtime_for_action blocks install when systemd is unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { echo "$*"; }
    systemctl_available() { return 1; }
    systemd_running() { return 1; }
    ALLOW_NO_SYSTEMD=false
    if require_systemd_runtime_for_action install; then
      echo "unexpected-success"
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "require_systemd_runtime_for_action allows compat mode with --allow-no-systemd" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { echo "$*"; }
    systemctl_available() { return 1; }
    systemd_running() { return 1; }
    ALLOW_NO_SYSTEMD=true
    require_systemd_runtime_for_action install
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "require_systemd_runtime_for_action blocks add-clients without systemd even in compat mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { echo "$*"; }
    systemctl_available() { return 1; }
    systemd_running() { return 1; }
    ALLOW_NO_SYSTEMD=true
    if require_systemd_runtime_for_action add-clients; then
      echo "unexpected-success"
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "systemd_running disables service management in isolated root contexts" {
    run bash -eo pipefail -c '
    grep -q '\''running_in_isolated_root_context'\'' ./modules/lib/system_runtime.sh
    grep -q '\''/proc/1/root/'\'' ./modules/lib/system_runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "atomic_write allows canonical systemd unit directories" {
    run bash -eo pipefail -c '
    grep -q '\''"/usr/lib/systemd"'\'' ./lib.sh
    grep -q '\''"/lib/systemd"'\'' ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "atomic_write guards against interactive stdin" {
    run bash -eo pipefail -c '
    grep -q '\''if \[\[ -t 0 \]\]; then'\'' ./lib.sh
    grep -q '\''atomic_write: вызван без stdin'\'' ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "status_flow verbose degrades gracefully when free/df are unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    grep -q '\''mem_info=$(free -m .*|| true)'\'' ./service.sh
    grep -q '\''disk_info=$(df -h / .*|| true)'\'' ./service.sh
    grep -q '\''Память: n/a'\'' ./service.sh
    grep -q '\''Диск:   n/a'\'' ./service.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "status_flow_render_config_summary warns on unknown transport" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    XRAY_CONFIG="$tmp"
    cat > "$XRAY_CONFIG" <<JSON
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "streamSettings": {
        "network": "quic",
        "realitySettings": {
          "dest": "example.com:443"
        }
      }
    }
  ]
}
JSON
    status_flow_render_config_summary
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Transport: unknown"* ]]
    [[ "$output" == *"нераспознанный транспорт"* ]]
}

@test "status_flow keeps major sections in stable order" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/xray"
    XRAY_CONFIG="$tmp/config.json"
    XRAY_KEYS="$tmp/keys"
    mkdir -p "$XRAY_KEYS"
    touch "$XRAY_KEYS/clients.txt" "$XRAY_KEYS/clients-links.txt"
    cat > "$XRAY_CONFIG" <<'"'"'EOF'"'"'
{"inbounds":[{"listen":"0.0.0.0","port":443,"streamSettings":{"network":"xhttp","realitySettings":{"dest":"example.com:443","serverNames":["example.com"],"fingerprint":"chrome"},"xhttpSettings":{"path":"/x"}},"settings":{"decryption":"none","clients":[{"flow":"xtls-rprx-vision"}]}}]}
EOF
    cat > "$XRAY_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "Xray 25.9.5"
EOF
    chmod +x "$XRAY_BIN"
    SERVER_IP="203.0.113.10"
    SERVER_IP6="2001:db8::10"
    VERBOSE=false
    systemctl() {
      if [[ "${1:-}" == "is-active" ]]; then
        return 0
      fi
      if [[ "${1:-}" == "show" && "${2:-}" == "xray" ]]; then
        echo "2026-03-15 12:00:00 UTC"
        return 0
      fi
      return 1
    }
    out="$(status_flow | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    xray_line="$(printf "%s\n" "$out" | grep -n "^Xray:" | head -n1 | cut -d: -f1)"
    server_line="$(printf "%s\n" "$out" | grep -n "^Сервер:" | head -n1 | cut -d: -f1)"
    clients_line="$(printf "%s\n" "$out" | grep -n "^Клиентские конфиги:" | head -n1 | cut -d: -f1)"
    test -n "$xray_line" -a -n "$server_line" -a -n "$clients_line"
    test "$xray_line" -lt "$server_line"
    test "$server_line" -lt "$clients_line"
    printf "%s\n" "$out" | grep -q "Подсказка: используйте --verbose для подробной информации"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "status_flow verbose shows source metadata section" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/xray"
    XRAY_CONFIG="$tmp/config.json"
    XRAY_KEYS="$tmp/keys"
    mkdir -p "$XRAY_KEYS"
    touch "$XRAY_KEYS/clients.txt"
    cat > "$XRAY_CONFIG" <<'"'"'EOF'"'"'
{"inbounds":[]}
EOF
    cat > "$XRAY_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "Xray 25.9.5"
EOF
    chmod +x "$XRAY_BIN"
    XRAY_SOURCE_KIND="bootstrap"
    XRAY_SOURCE_REF="v7.5.2"
    XRAY_SOURCE_COMMIT="2fba5138b5e629891ef92f909f163af0b1a988d9"
    VERBOSE=true
    systemctl() { return 1; }
    out="$(status_flow | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    printf "%s\n" "$out" | grep -q "^Source metadata:"
    printf "%s\n" "$out" | grep -q "Kind: bootstrap"
    printf "%s\n" "$out" | grep -q "Ref: v7.5.2"
    printf "%s\n" "$out" | grep -q "Commit: 2fba5138b5e629891ef92f909f163af0b1a988d9"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "logs_flow falls back to xray-health journal when health log file is absent" {
    run bash -eo pipefail -c '
    grep -Fq '\''journalctl -u xray-health.service -n "$lines" --no-pager'\'' ./service.sh
    grep -Fq '\''journalctl -u xray-health.service -n 10 --no-pager'\'' ./service.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "status_flow verbose falls back when transport helper functions are unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    unset -f transport_endpoint_label transport_display_name
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/xray"
    XRAY_CONFIG="$tmp/config.json"
    XRAY_KEYS="$tmp/keys"
    mkdir -p "$XRAY_KEYS"
    touch "$XRAY_KEYS/clients.txt"
    cat > "$XRAY_CONFIG" <<'"'"'EOF'"'"'
{"inbounds":[{"listen":"0.0.0.0","port":443,"streamSettings":{"network":"xhttp","realitySettings":{"dest":"example.com:443","serverNames":["example.com"],"fingerprint":"chrome"},"xhttpSettings":{"path":"/x"}},"settings":{"decryption":"none","clients":[{"flow":"xtls-rprx-vision"}]}}]}
EOF
    cat > "$XRAY_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "Xray 25.9.5"
EOF
    chmod +x "$XRAY_BIN"
    VERBOSE=true
    systemctl() { return 1; }
    out="$(status_flow | sed -E "s/\x1B\\[[0-9;]*[A-Za-z]//g")"
    printf "%s\n" "$out" | grep -q "Transport:   xhttp"
    printf "%s\n" "$out" | grep -q "endpoint: /x"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "diagnose keeps errexit enabled in caller shell" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./health.sh

    tmp_log=$(mktemp)
    trap "rm -f \"$tmp_log\"" EXIT

    DIAG_LOG="$tmp_log"
    XRAY_BIN="/nonexistent/xray"
    XRAY_CONFIG="/nonexistent/config.json"

    log() { :; }
    systemctl() { return 0; }
    journalctl() { return 0; }
    ss() { return 0; }
    df() { return 0; }
    free() { return 0; }

    diagnose
    set -o | grep -Eq "^errexit[[:space:]]+on$"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "source metadata and hotspot phase helpers are wired into runtime modules" {
    run bash -eo pipefail -c '
    grep -Fq '\''XRAY_SOURCE_KIND="${XRAY_SOURCE_KIND:-}"'\'' ./lib.sh
    grep -Fq '\''write_env_kv XRAY_SOURCE_KIND'\'' ./modules/config/runtime_apply.sh
    grep -Fq '\''XRAY_SOURCE_KIND)'\'' ./modules/lib/config_loading.sh
    grep -Fq '\''===== SOURCE ====='\'' ./health.sh
    grep -Fq '\''status_flow_render_verbose_source() {'\'' ./service.sh
    grep -Fq '\''export_wrapper_source_metadata() {'\'' ./xray-reality.sh
    grep -Fq '\''parse_args_collect_tokens() {'\'' ./modules/lib/cli.sh
    grep -Fq '\''parse_args_apply_action_positionals() {'\'' ./modules/lib/cli.sh
    grep -Fq '\''strict_validate_runtime_safe_vars() {'\'' ./modules/lib/runtime_inputs.sh
    grep -Fq '\''strict_validate_runtime_action_contracts() {'\'' ./modules/lib/runtime_inputs.sh
    grep -Fq '\''create_systemd_service_prepare_values() {'\'' ./modules/service/runtime.sh
    grep -Fq '\''create_systemd_service_activate_unit() {'\'' ./modules/service/runtime.sh
    grep -Fq '\''self_check_run_variant_probe_prepare_runtime() {'\'' ./modules/health/self_check.sh
    grep -Fq '\''self_check_run_variant_probe_result_json() {'\'' ./modules/health/self_check.sh
    grep -Fq '\''rebuild_config_prepare_transport_context() {'\'' ./config.sh
    grep -Fq '\''rebuild_config_commit_runtime_state_from_payload() {'\'' ./config.sh
    grep -Fq '\''save_client_configs_validate_prerequisites() {'\'' ./modules/config/client_formats.sh
    grep -Fq '\''save_client_configs_build_inventory() {'\'' ./modules/config/client_formats.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release workflow avoids curl pipe sh and unpinned release action" {
    run bash -eo pipefail -c '
    grep -q '\''gh release create'\'' ./.github/workflows/release.yml
    grep -q '\''default_branch="${{ github.event.repository.default_branch }}"'\'' ./.github/workflows/release.yml
    ! grep -q '\''origin/main'\'' ./.github/workflows/release.yml
    ! grep -Eq '\''curl[[:space:]]+-sSfL[[:space:]]+https://raw.githubusercontent.com/anchore/syft/main/install.sh[[:space:]]*\\|[[:space:]]*sudo[[:space:]]+sh'\'' ./.github/workflows/release.yml
    ! grep -q '\''softprops/action-gh-release'\'' ./.github/workflows/release.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release workflow excludes helper/nightly e2e scripts from release matrix" {
    run bash -eo pipefail -c '
    grep -Fq "find tests/e2e -maxdepth 1 -type f -name" ./.github/workflows/release.yml
    grep -Fq "! -name '\''lib.sh'\''" ./.github/workflows/release.yml
    grep -Fq "! -name '\''nightly_smoke_install_add_update_uninstall.sh'\''" ./.github/workflows/release.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release script pushes current branch instead of hardcoded main" {
    run bash -eo pipefail -c '
    grep -q '\''git push origin "\$push_branch"'\'' ./scripts/release.sh
    ! grep -q '\''git push origin main'\'' ./scripts/release.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release script uses portable replacements instead of sed -i" {
    run bash -eo pipefail -c '
    grep -q '\''replace_with_sed()'\'' ./scripts/release.sh
    ! grep -q '\''sed -i'\'' ./scripts/release.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release script enforces non-empty notes and no TODO in target release section" {
    run bash -eo pipefail -c '
    grep -Fq '\''validate_generated_release_notes()'\'' ./scripts/release.sh
    grep -Fq '\''ensure_release_section_has_no_todo()'\'' ./scripts/release.sh
    grep -Fq '\''print_release_section('\'' ./scripts/release.sh
    grep -Fq '\''CHANGELOG_RU="$ROOT_DIR/docs/ru/CHANGELOG.md"'\'' ./scripts/release.sh
    grep -Fq '\''BUG_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.yml"'\'' ./scripts/release.sh
    grep -Fq '\''SUPPORT_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/support_request.yml"'\'' ./scripts/release.sh
    grep -Fq '\''tolower($0) ~ /^## \[unreleased\]/'\'' ./scripts/release.sh
    grep -Fq '\''Generated release notes are empty; refusing release.'\'' ./scripts/release.sh
    grep -Fq '\''still contains TODO placeholder'\'' ./scripts/release.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release script consumes unreleased changelog notes into target section" {
    run bash -eo pipefail -c '
    tmp_repo=$(mktemp -d)
    trap '\''rm -rf "$tmp_repo"'\'' EXIT

    mkdir -p "$tmp_repo/scripts" "$tmp_repo/docs/en" "$tmp_repo/docs/ru" "$tmp_repo/.github/ISSUE_TEMPLATE"
    cp ./scripts/release.sh "$tmp_repo/scripts/release.sh"
    chmod +x "$tmp_repo/scripts/release.sh"
    cat > "$tmp_repo/scripts/check-release-consistency.sh" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$tmp_repo/scripts/check-release-consistency.sh"

    cat > "$tmp_repo/lib.sh" <<'\''EOF'\''
#!/usr/bin/env bash
# Network Stealth Core 1.0.0 - Example
readonly SCRIPT_VERSION="1.0.0"
EOF

    cat > "$tmp_repo/xray-reality.sh" <<'\''EOF'\''
#!/usr/bin/env bash
# Network Stealth Core 1.0.0 - Wrapper
EOF

    cat > "$tmp_repo/README.md" <<'\''EOF'\''
[![release](https://img.shields.io/badge/release-v1.0.0-blue)](https://example.invalid)
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v1.0.0/xray-reality.sh -o /tmp/xray-reality.sh
XRAY_REPO_REF=v1.0.0 bash /tmp/xray-reality.sh install
EOF

    cat > "$tmp_repo/README.ru.md" <<'\''EOF'\''
[![release](https://img.shields.io/badge/release-v1.0.0-blue)](https://example.invalid)
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v1.0.0/xray-reality.sh -o /tmp/xray-reality.sh
XRAY_REPO_REF=v1.0.0 bash /tmp/xray-reality.sh install
EOF

    cat > "$tmp_repo/.github/ISSUE_TEMPLATE/bug_report.yml" <<'\''EOF'\''
placeholder: v1.0.0 / <full_commit_sha> / ubuntu@<sha>
EOF

    cat > "$tmp_repo/.github/ISSUE_TEMPLATE/support_request.yml" <<'\''EOF'\''
placeholder: v1.0.0 / <full_commit_sha> / ubuntu@<sha>
EOF

    cat > "$tmp_repo/.github/SECURITY.md" <<'\''EOF'\''
# security policy

| version line | status |
|---|---|
| `1.0.x` | supported |
| `<1.0` | unsupported in this repository |
EOF

    cat > "$tmp_repo/.github/SECURITY.ru.md" <<'\''EOF'\''
# политика безопасности

| линейка версий | статус |
|---|---|
| `1.0.x` | поддерживается |
| `<1.0` | не поддерживается в этом репозитории |
EOF

    cat > "$tmp_repo/docs/en/CHANGELOG.md" <<'\''EOF'\''
# changelog

## [unreleased]

### Changed
- unreleased note one
- unreleased note two

## [1.0.0] - 2026-03-17

### Changed
- base release
EOF

    cat > "$tmp_repo/docs/ru/CHANGELOG.md" <<'\''EOF'\''
# changelog

## [unreleased]

### Changed
- unreleased note one
- unreleased note two

## [1.0.0] - 2026-03-17

### Changed
- base release
EOF

    git -C "$tmp_repo" init -q
    git -C "$tmp_repo" config user.name '\''Test User'\''
    git -C "$tmp_repo" config user.email '\''test@example.com'\''
    git -C "$tmp_repo" add .
    git -C "$tmp_repo" commit -qm '\''base'\''
    git -C "$tmp_repo" tag -a v1.0.0 -m '\''v1.0.0'\''
    printf '\''\n# post-tag change\n'\'' >> "$tmp_repo/lib.sh"
    git -C "$tmp_repo" add lib.sh
    git -C "$tmp_repo" commit -qm '\''post-tag change'\''

    (cd "$tmp_repo" && bash ./scripts/release.sh 1.0.1)

    awk '\''BEGIN { in_unreleased = 0; saw_body = 0 }
         /^## \[unreleased\]/ { in_unreleased = 1; next }
         /^## \[/ { if (in_unreleased) in_unreleased = 0 }
         in_unreleased && $0 ~ /[^[:space:]]/ { saw_body = 1 }
         END { exit saw_body ? 1 : 0 }'\'' "$tmp_repo/docs/en/CHANGELOG.md"
    awk '\''BEGIN { in_target = 0; changed_headers = 0; note1 = 0; note2 = 0 }
         /^## \[1\.0\.1\]/ { in_target = 1; next }
         /^## \[/ { if (in_target) in_target = 0 }
         in_target && /^### Changed$/ { changed_headers++ }
         in_target && /- unreleased note one/ { note1 = 1 }
         in_target && /- unreleased note two/ { note2 = 1 }
         END { exit (changed_headers == 1 && note1 && note2) ? 0 : 1 }'\'' "$tmp_repo/docs/en/CHANGELOG.md"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "release consistency check enforces changelog bullets and blocks TODO in released sections" {
    run bash -eo pipefail -c '
    grep -Fq '\''CHANGELOG_FILE_RU="$ROOT_DIR/docs/ru/CHANGELOG.md"'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''BUG_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.yml"'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''SUPPORT_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/support_request.yml"'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''latest_local_semver_tag()'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''check_unreleased_branch_state()'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''docs/en/CHANGELOG.md must keep non-empty [unreleased] notes while HEAD is ahead of ${latest_tag}'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''if [[ "$latest_tag" != "v${script_version}" ]]; then'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''docs/ru/CHANGELOG.md section'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''README.md release-tag bootstrap url'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''README.ru.md release-tag bootstrap ref'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''bug template placeholder'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''support template placeholder'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''RU CHANGELOG section [${script_version}] does not contain release bullet notes'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''CHANGELOG contains TODO placeholder inside a released section'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''RU CHANGELOG contains TODO placeholder inside a released section'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''does not contain release bullet notes'\'' ./scripts/check-release-consistency.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release consistency check rejects TODO placeholder in released ru changelog section" {
    run bash -eo pipefail -c '
    tmp_repo=$(mktemp -d)
    trap '\''rm -rf "$tmp_repo"'\'' EXIT

    mkdir -p "$tmp_repo/scripts" "$tmp_repo/docs/en" "$tmp_repo/docs/ru" "$tmp_repo/.github/ISSUE_TEMPLATE"
    cp ./scripts/check-release-consistency.sh "$tmp_repo/scripts/check-release-consistency.sh"
    chmod +x "$tmp_repo/scripts/check-release-consistency.sh"

    cat > "$tmp_repo/lib.sh" <<'\''EOF'\''
#!/usr/bin/env bash
# Network Stealth Core 1.0.0 - Example
readonly SCRIPT_VERSION="1.0.0"
EOF

    cat > "$tmp_repo/xray-reality.sh" <<'\''EOF'\''
#!/usr/bin/env bash
# Network Stealth Core 1.0.0 - Wrapper
EOF

    cat > "$tmp_repo/README.md" <<'\''EOF'\''
[![release](https://img.shields.io/badge/release-v1.0.0-blue)](https://example.invalid)
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v1.0.0/xray-reality.sh -o /tmp/xray-reality.sh
XRAY_REPO_REF=v1.0.0 bash /tmp/xray-reality.sh install
EOF

    cat > "$tmp_repo/README.ru.md" <<'\''EOF'\''
[![release](https://img.shields.io/badge/release-v1.0.0-blue)](https://example.invalid)
curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/v1.0.0/xray-reality.sh -o /tmp/xray-reality.sh
XRAY_REPO_REF=v1.0.0 bash /tmp/xray-reality.sh install
EOF

    cat > "$tmp_repo/.github/ISSUE_TEMPLATE/bug_report.yml" <<'\''EOF'\''
      placeholder: v1.0.0 / <full_commit_sha> / ubuntu@<sha>
EOF

    cat > "$tmp_repo/.github/ISSUE_TEMPLATE/support_request.yml" <<'\''EOF'\''
      placeholder: v1.0.0 / <full_commit_sha> / ubuntu@<sha>
EOF

    cat > "$tmp_repo/.github/SECURITY.md" <<'\''EOF'\''
# security policy
| version line | status |
|---|---|
| `1.0.x` | supported |
| `<1.0` | unsupported in this repository |
EOF

    cat > "$tmp_repo/.github/SECURITY.ru.md" <<'\''EOF'\''
# политика безопасности
| линейка версий | статус |
|---|---|
| `1.0.x` | поддерживается |
| `<1.0` | не поддерживается в этом репозитории |
EOF

    cat > "$tmp_repo/docs/en/CHANGELOG.md" <<'\''EOF'\''
# changelog

## [unreleased]

### Changed
- unreleased note

## [1.0.0] - 2026-03-20

### Fixed
- released note
EOF

    cat > "$tmp_repo/docs/ru/CHANGELOG.md" <<'\''EOF'\''
# changelog

## [unreleased]

### Changed
- unreleased note

## [1.0.0] - 2026-03-20

### Fixed
- TODO: summarize release changes
EOF

    cd "$tmp_repo"
    bash ./scripts/check-release-consistency.sh
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"RU CHANGELOG contains TODO placeholder inside a released section"* ]]
}

@test "os matrix workflow tracks supported ubuntu image" {
    run bash -eo pipefail -c '
    grep -q '\''name: ubuntu-24.04'\'' ./.github/workflows/os-matrix-smoke.yml
    grep -q '\''image: ubuntu:24.04'\'' ./.github/workflows/os-matrix-smoke.yml
    grep -Fq -- '\''- ubuntu'\'' ./.github/workflows/os-matrix-smoke.yml
    grep -Fq -- '\''- main'\'' ./.github/workflows/os-matrix-smoke.yml
    grep -Fq -- '\''- ubuntu'\'' ./.github/workflows/packages.yml
    grep -Fq -- '\''- main'\'' ./.github/workflows/packages.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "os matrix workflow excludes legacy fedora/almalinux entries" {
    run bash -eo pipefail -c '
    ! grep -q '\''name: fedora-41'\'' ./.github/workflows/os-matrix-smoke.yml
    ! grep -q '\''image: fedora:41'\'' ./.github/workflows/os-matrix-smoke.yml
    ! grep -q '\''name: almalinux-9'\'' ./.github/workflows/os-matrix-smoke.yml
    ! grep -q '\''image: almalinux:9'\'' ./.github/workflows/os-matrix-smoke.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "ci workflow includes stability and quality gates" {
    run bash -eo pipefail -c '
    grep -q '\''name: stability smoke (double bats)'\'' ./.github/workflows/ci.yml
    grep -q '\''run: make lint'\'' ./.github/workflows/ci.yml
    grep -q '\''run: make test'\'' ./.github/workflows/ci.yml
    grep -q '\''COMPLEXITY_STAGE=3 bash scripts/check-shell-complexity.sh'\'' ./.github/workflows/ci.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "quality scripts exist and are wired into lint pipeline" {
    run bash -eo pipefail -c '
    test -f ./scripts/check-workflow-pinning.sh
    test -f ./scripts/check-security-baseline.sh
    test -f ./scripts/check-docs-commands.sh
    grep -q '\''check-workflow-pinning.sh'\'' ./tests/lint.sh
    grep -q '\''check-security-baseline.sh'\'' ./tests/lint.sh
    grep -q '\''check-docs-commands.sh'\'' ./tests/lint.sh
    grep -q '\''check-workflow-pinning.sh'\'' ./Makefile
    grep -q '\''check-security-baseline.sh'\'' ./Makefile
    grep -q '\''check-docs-commands.sh'\'' ./Makefile
    grep -q '\''command -v bashate'\'' ./Makefile
    grep -q '\''bashate -i E003,E006,E042,E043'\'' ./Makefile
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "docs command checker covers maintainer lab docs" {
    run bash -eo pipefail -c '
    test -f ./docs/en/MAINTAINER-LAB.md
    test -f ./docs/ru/MAINTAINER-LAB.md
    test -f ./docs/en/FIELD-VALIDATION.md
    test -f ./docs/ru/FIELD-VALIDATION.md
    grep -q '\''docs/en/MAINTAINER-LAB.md'\'' ./scripts/check-docs-commands.sh
    grep -q '\''docs/ru/MAINTAINER-LAB.md'\'' ./scripts/check-docs-commands.sh
    grep -q '\''docs/en/FIELD-VALIDATION.md'\'' ./scripts/check-docs-commands.sh
    grep -q '\''docs/ru/FIELD-VALIDATION.md'\'' ./scripts/check-docs-commands.sh
    grep -Fq "[MAINTAINER-LAB.md](MAINTAINER-LAB.md)" ./docs/en/INDEX.md
    grep -Fq "[MAINTAINER-LAB.md](MAINTAINER-LAB.md)" ./docs/ru/INDEX.md
    grep -Fq "[FIELD-VALIDATION.md](FIELD-VALIDATION.md)" ./docs/en/INDEX.md
    grep -Fq "[FIELD-VALIDATION.md](FIELD-VALIDATION.md)" ./docs/ru/INDEX.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "docs command checker enforces pinned bootstrap before floating bootstrap" {
    run bash -eo pipefail -c '
    grep -q '\''check_pinned_bootstrap_order README.md'\'' ./scripts/check-docs-commands.sh
    grep -q '\''check_pinned_bootstrap_order README.ru.md'\'' ./scripts/check-docs-commands.sh
    pinned_en="$(grep -n '\''XRAY_REPO_COMMIT=<full_commit_sha>'\'' ./README.md | head -n1 | cut -d: -f1)"
    tag_en="$(grep -nE '\''XRAY_REPO_REF=v[0-9]+\.[0-9]+\.[0-9]+'\'' ./README.md | head -n1 | cut -d: -f1)"
    floating_en="$(grep -n '\''^sudo bash /tmp/xray-reality.sh install$'\'' ./README.md | head -n1 | cut -d: -f1)"
    pinned_ru="$(grep -n '\''XRAY_REPO_COMMIT=<full_commit_sha>'\'' ./README.ru.md | head -n1 | cut -d: -f1)"
    tag_ru="$(grep -nE '\''XRAY_REPO_REF=v[0-9]+\.[0-9]+\.[0-9]+'\'' ./README.ru.md | head -n1 | cut -d: -f1)"
    floating_ru="$(grep -n '\''^sudo bash /tmp/xray-reality.sh install$'\'' ./README.ru.md | head -n1 | cut -d: -f1)"
    test -n "$pinned_en" -a -n "$tag_en" -a -n "$floating_en" -a "$pinned_en" -lt "$tag_en" -a "$tag_en" -lt "$floating_en"
    test -n "$pinned_ru" -a -n "$tag_ru" -a -n "$floating_ru" -a "$pinned_ru" -lt "$tag_ru" -a "$tag_ru" -lt "$floating_ru"
    grep -q '\''XRAY_REPO_REF=v<release-tag>'\'' ./docs/en/FAQ.md
    grep -q '\''XRAY_REPO_REF=v<release-tag>'\'' ./docs/ru/FAQ.md
    grep -q '\''XRAY_REPO_REF=v<release-tag>'\'' ./docs/en/OPERATIONS.md
    grep -q '\''XRAY_REPO_REF=v<release-tag>'\'' ./docs/ru/OPERATIONS.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "docs and helpers use shell-safe browser dialer guidance" {
    run bash -eo pipefail -c '
    for file in ./export.sh ./docs/en/OPERATIONS.md ./docs/ru/OPERATIONS.md ./docs/en/TROUBLESHOOTING.md ./docs/ru/TROUBLESHOOTING.md; do
      ! grep -q '\''export xray\.browser\.dialer='\'' "$file"
    done
    grep -Fq "env '\''xray.browser.dialer=127.0.0.1:11050'\'' xray run -config raw-xray/<emergency-config>.json" ./export.sh
    grep -Fq "browser_dialer_env/browser_dialer_address from manifest.json" ./export.sh
    grep -Fq "env '\''xray.browser.dialer=127.0.0.1:11050'\'' xray run -config /path/to/emergency.json" ./docs/en/OPERATIONS.md
    grep -Fq "env '\''xray.browser.dialer=127.0.0.1:11050'\'' xray run -config /path/to/emergency.json" ./docs/ru/OPERATIONS.md
    grep -Fq "env '\''xray.browser.dialer=127.0.0.1:11050'\'' xray run -config /path/to/emergency.json" ./docs/en/TROUBLESHOOTING.md
    grep -Fq "env '\''xray.browser.dialer=127.0.0.1:11050'\'' xray run -config /path/to/emergency.json" ./docs/ru/TROUBLESHOOTING.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "release tooling covers security version surface" {
    run bash -eo pipefail -c '
    version="$(sed -n '\''s/^readonly SCRIPT_VERSION="\([0-9.]*\)"/\1/p'\'' ./lib.sh)"
    supported_line="${version%.*}.x"
    unsupported_line="<${version%.*}"
    grep -Fq '\''SECURITY_EN="$ROOT_DIR/.github/SECURITY.md"'\'' ./scripts/release.sh
    grep -Fq '\''SECURITY_RU="$ROOT_DIR/.github/SECURITY.ru.md"'\'' ./scripts/release.sh
    grep -Fq '\''supported_minor_line="${VERSION%.*}.x"'\'' ./scripts/release.sh
    grep -Fq '\''unsupported_before_line="<${VERSION%.*}"'\'' ./scripts/release.sh
    grep -Fq '\''SECURITY_EN="$ROOT_DIR/.github/SECURITY.md"'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''SECURITY_RU="$ROOT_DIR/.github/SECURITY.ru.md"'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''SECURITY.md supported version line'\'' ./scripts/check-release-consistency.sh
    grep -Fq '\''SECURITY.ru.md supported version line'\'' ./scripts/check-release-consistency.sh
    grep -Fq "| \`${supported_line}\` | supported |" ./.github/SECURITY.md
    grep -Fq "| \`${unsupported_line}\` | unsupported in this repository |" ./.github/SECURITY.md
    grep -Fq "| \`${supported_line}\` | поддерживается |" ./.github/SECURITY.ru.md
    grep -Fq "| \`${unsupported_line}\` | не поддерживается в этом репозитории |" ./.github/SECURITY.ru.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "shared runtime modules keep canonical self-check urls default" {
    run bash -eo pipefail -c '
    canonical="https://cp.cloudflare.com/generate_204,https://www.gstatic.com/generate_204"
    grep -Fq ": \"\${SELF_CHECK_URLS:=$canonical}\"" ./modules/lib/globals_contract.sh
    grep -Fq ": \"\${SELF_CHECK_URLS:=$canonical}\"" ./modules/lib/runtime_inputs.sh
    grep -Fq "\${SELF_CHECK_URLS:-$canonical}" ./modules/health/self_check.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "user-facing docs do not embed vm helper commands" {
    run bash -eo pipefail -c '
    ! grep -R -n -E "nsc-vm-install-(latest|repo)" \
      ./README.md ./README.ru.md ./docs/en/OPERATIONS.md ./docs/ru/OPERATIONS.md \
      ./docs/en/FAQ.md ./docs/ru/FAQ.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "docs and workflows separate nightly self-hosted evidence from manual smoke" {
    run bash -eo pipefail -c '
    grep -Fq "Nightly Smoke" ./docs/en/MAINTAINER-LAB.md
    grep -Fq "self-hosted-smoke.yml" ./docs/en/MAINTAINER-LAB.md
    grep -Fq "Nightly Smoke" ./docs/ru/MAINTAINER-LAB.md
    grep -Fq "self-hosted-smoke.yml" ./docs/ru/MAINTAINER-LAB.md
    grep -Fq "Nightly Smoke" ./.github/CONTRIBUTING.md
    grep -Fq "self-hosted-smoke.yml" ./.github/CONTRIBUTING.md
    grep -Fq "Nightly Smoke" ./.github/CONTRIBUTING.ru.md
    grep -Fq "self-hosted-smoke.yml" ./.github/CONTRIBUTING.ru.md
    grep -Fq "name: Self-hosted Smoke (manual)" ./.github/workflows/self-hosted-smoke.yml
    grep -Fq "Regular self-hosted evidence lives in Nightly Smoke; this workflow is manual/on-demand only." ./.github/workflows/self-hosted-smoke.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "make test enforces utf8 locale fallback for bats" {
    run bash -eo pipefail -c '
    grep -Fq '\''LANG="$${LANG:-C.UTF-8}" LC_ALL="$${LC_ALL:-C.UTF-8}" bats tests/bats'\'' ./Makefile
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "makefile exposes ci-fast ci-full and lab targets" {
    run bash -eo pipefail -c '
    grep -q "^ci-fast:" ./Makefile
    grep -q "^ci-full:" ./Makefile
    grep -q "^lab-smoke:" ./Makefile
    grep -q "^vm-lab-prepare:" ./Makefile
    grep -q "^vm-lab-smoke:" ./Makefile
    grep -q "^vm-proof-pack:" ./Makefile
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "make lint actionlints self-hosted smoke workflow" {
    run bash -eo pipefail -c '
    grep -q '\''^WORKFLOWS := .*\.github/workflows/self-hosted-smoke\.yml'\'' ./Makefile
    grep -q '\''actionlint -oneline $(WORKFLOWS)'\'' ./Makefile
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "self_check_post_action_verdict reports broken when runtime artifacts are missing" {
    run bash -eo pipefail -c '
    source ./modules/health/self_check.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/missing-xray"
    XRAY_CONFIG="$tmp/missing-config.json"
    XRAY_KEYS="$tmp/keys"
    XRAY_GROUP="root"
    SELF_CHECK_STATE_FILE="$tmp/state/self-check.json"
    SELF_CHECK_HISTORY_FILE="$tmp/state/self-check-history.ndjson"
    self_check_log() { printf "%s %s\n" "$1" "$2"; }
    if self_check_post_action_verdict install; then
      echo "unexpected-success"
      exit 1
    fi
    test -f "$SELF_CHECK_STATE_FILE"
    jq -e ".verdict == \"broken\"" "$SELF_CHECK_STATE_FILE" > /dev/null
    grep -q "бинарник xray не найден" "$SELF_CHECK_STATE_FILE"
    grep -q "конфиг не найден" "$SELF_CHECK_STATE_FILE"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "self_check_post_action_verdict warns on loopback runtime without transport probe" {
    run bash -eo pipefail -c '
    source ./modules/health/self_check.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/xray"
    XRAY_CONFIG="$tmp/config.json"
    XRAY_KEYS="$tmp/keys"
    XRAY_GROUP="root"
    SELF_CHECK_STATE_FILE="$tmp/state/self-check.json"
    SELF_CHECK_HISTORY_FILE="$tmp/state/self-check-history.ndjson"
    mkdir -p "$XRAY_KEYS"
    printf "#!/usr/bin/env bash\nexit 0\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    printf "{}\n" > "$XRAY_CONFIG"
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 1; }
    systemd_running() { return 1; }
    SERVER_IP="127.0.0.1"
    self_check_log() { printf "%s %s\n" "$1" "$2"; }
    self_check_post_action_verdict install
    jq -e ".verdict == \"warning\"" "$SELF_CHECK_STATE_FILE" > /dev/null
    grep -q "loopback install detected: transport-aware self-check пропущен" "$SELF_CHECK_STATE_FILE"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "self_check_post_action_verdict stores selected successful variant" {
    run bash -eo pipefail -c '
    source ./modules/health/self_check.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    XRAY_BIN="$tmp/xray"
    XRAY_CONFIG="$tmp/config.json"
    XRAY_KEYS="$tmp/keys"
    XRAY_GROUP="root"
    SELF_CHECK_STATE_FILE="$tmp/state/self-check.json"
    SELF_CHECK_HISTORY_FILE="$tmp/state/self-check-history.ndjson"
    mkdir -p "$XRAY_KEYS"
    printf "#!/usr/bin/env bash\nexit 0\n" > "$XRAY_BIN"
    chmod +x "$XRAY_BIN"
    printf "{}\n" > "$XRAY_CONFIG"
    cat > "$XRAY_KEYS/clients.json" <<'"'"'EOF'"'"'
{"configs":[{"recommended_variant":"recommended"}]}
EOF
    xray_config_test_ok() { return 0; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    systemctl() { [[ "${1:-}" == "is-active" ]] && return 0; return 1; }
    self_check_log() { printf "%s %s\n" "$1" "$2"; }
    self_check_config_job_json() {
      jq -n '\''{config_name:"Config 1", mode:"auto"}'\''
    }
    self_check_preferred_variant_keys() {
      printf "recommended\n"
    }
    self_check_first_raw_file_for_job() {
      printf "ipv4\t%s/raw.json\n" "$tmp"
    }
    self_check_run_variant_probe() {
      jq -n '\''{
        checked_at:"2026-03-15T12:00:00Z",
        action:"install",
        config_name:"Config 1",
        variant_key:"recommended",
        mode:"auto",
        ip_family:"ipv4",
        raw_config_file:"raw.json",
        success:true,
        latency_ms:91,
        selected_url:"https://cp.cloudflare.com/generate_204",
        probe_results:[]
      }'\''
    }
    self_check_post_action_verdict install
    jq -e ".verdict == \"ok\"" "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e ".selected_variant.config_name == \"Config 1\"" "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e ".selected_variant.variant_key == \"recommended\"" "$SELF_CHECK_STATE_FILE" > /dev/null
    jq -e ".attempted_variants | length == 1" "$SELF_CHECK_STATE_FILE" > /dev/null
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"selected variant: Config 1 / recommended / ipv4 / 91ms"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "service, health, and export modules are wired into lint and dead-function coverage" {
    run bash -eo pipefail -c '
    grep -Fq "modules/service/*.sh" ./Makefile
    grep -Fq "modules/health/*.sh" ./Makefile
    grep -Fq "modules/export/*.sh" ./Makefile
    grep -Fq '"'"'$ROOT_DIR"'"'"/modules/service/*.sh' ./scripts/check-dead-functions.sh
    grep -Fq '"'"'$ROOT_DIR"'"'"/modules/health/*.sh' ./scripts/check-dead-functions.sh
    grep -Fq '"'"'$ROOT_DIR"'"'"/modules/export/*.sh' ./scripts/check-dead-functions.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install flow warns when export module is unavailable" {
    run bash -eo pipefail -c '
    grep -Fq '\''Модуль export.sh не загружен; экспорт клиентских конфигов и canary bundle пропущен'\'' ./install.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lab scripts are wired into lint and self-hosted workflows" {
    run bash -eo pipefail -c '
    grep -q '\''scripts/lab/\*.sh'\'' ./Makefile
    grep -q '\''scripts/lab/\*.sh'\'' ./tests/lint.sh
    grep -q '\''make vm-lab-smoke'\'' ./.github/workflows/self-hosted-smoke.yml
    grep -q '\''make lab-smoke'\'' ./.github/workflows/self-hosted-smoke.yml
    grep -q '\''make vm-lab-smoke'\'' ./.github/workflows/nightly-smoke.yml
    grep -q '\''make lab-smoke'\'' ./.github/workflows/nightly-smoke.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "vm proof-pack target and workflow artifact upload are wired" {
    run bash -eo pipefail -c '
    grep -q '\''bash scripts/lab/generate-vm-proof-pack.sh'\'' ./Makefile
    grep -q '\''Generate vm proof-pack'\'' ./.github/workflows/self-hosted-smoke.yml
    grep -q '\''Upload vm proof-pack'\'' ./.github/workflows/self-hosted-smoke.yml
    grep -q '\''Generate vm proof-pack'\'' ./.github/workflows/nightly-smoke.yml
    grep -q '\''Upload vm proof-pack'\'' ./.github/workflows/nightly-smoke.yml
    grep -q '\''nightly-self-hosted-vm-proof-pack'\'' ./.github/workflows/nightly-smoke.yml
    grep -q '\''self-hosted-vm-proof-pack'\'' ./.github/workflows/self-hosted-smoke.yml
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "generate-vm-proof-pack builds sanitized bundle from latest vm run" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    ts="20260312T010203Z"
    proof_src="$tmp/vm/artifacts/proof-$ts"
    mkdir -p "$tmp/vm/workspace" "$tmp/vm/logs" "$proof_src"

    cat > "$tmp/vm/workspace/latest-vm-run.env" << EOF
LAB_VM_TIMESTAMP=$ts
LAB_VM_PROOF_DIR=$proof_src
LAB_VM_NAME=nsc-vm-2404
LAB_VM_SSH_PORT=10022
EOF

    cat > "$proof_src/lifecycle.json" << EOF
{"steps":[{"step":"install","status":"ok"}]}
EOF
    cat > "$proof_src/status-verbose.txt" << EOF
vless://123e4567-e89b-12d3-a456-426614174000@test-host:443?pbk=secret&sid=beef
EOF
    cat > "$tmp/vm/logs/vm-smoke-$ts.log" << EOF
raw log vless://123e4567-e89b-12d3-a456-426614174000@test-host:443?pbk=secret&sid=beef
EOF
    cat > "$tmp/vm/workspace/lab-vm-summary-$ts.json" << EOF
{"timestamp":"$ts","vm_name":"nsc-vm-2404"}
EOF

    output="$(LAB_HOST_ROOT="$tmp" bash ./scripts/lab/generate-vm-proof-pack.sh)"
    archive="$output"
    manifest="$tmp/vm/proof-pack/$ts/manifest.json"
    bundle_dir="$tmp/vm/proof-pack/$ts/bundle"
    latest_env="$tmp/vm/workspace/latest-proof-pack.env"

    test -f "$archive"
    test -f "$manifest"
    test -f "$latest_env"
    test -f "$bundle_dir/logs/vm-smoke.log"
    test -f "$bundle_dir/evidence/lifecycle.json"
    grep -q "VLESS-REDACTED" "$bundle_dir/logs/vm-smoke.log"
    ! grep -q "vless://" "$bundle_dir/logs/vm-smoke.log"
    jq -e ".timestamp == \"$ts\"" "$manifest" > /dev/null
    jq -e "any(.files[]; .path == \"logs/vm-smoke.log\")" "$manifest" > /dev/null
    grep -q "LAB_VM_PROOF_PACK_TAR=$archive" "$latest_env"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "public repo hygiene templates exist" {
    run bash -eo pipefail -c '
    test -f ./.github/ISSUE_TEMPLATE/bug_report.yml
    test -f ./.github/ISSUE_TEMPLATE/support_request.yml
    test -f ./.github/ISSUE_TEMPLATE/feature_request.yml
    test -f ./.github/ISSUE_TEMPLATE/config.yml
    test -f ./.github/PULL_REQUEST_TEMPLATE.md
    grep -q '\''proof-pack or lab evidence'\'' ./.github/PULL_REQUEST_TEMPLATE.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lib sources extracted ui runtime download config and path-safety modules" {
    run bash -eo pipefail -c '
    grep -q '\''LIB_UI_LOGGING_MODULE='\'' ./lib.sh
    grep -q '\''LIB_SYSTEM_RUNTIME_MODULE='\'' ./lib.sh
    grep -q '\''LIB_DOWNLOADS_MODULE='\'' ./lib.sh
    grep -q '\''LIB_CONFIG_LOADING_MODULE='\'' ./lib.sh
    grep -q '\''LIB_PATH_SAFETY_MODULE='\'' ./lib.sh
    grep -q '\''LIB_RUNTIME_INPUTS_MODULE='\'' ./lib.sh
    grep -q '\''source "$LIB_UI_LOGGING_MODULE"'\'' ./lib.sh
    grep -q '\''source "$LIB_SYSTEM_RUNTIME_MODULE"'\'' ./lib.sh
    grep -q '\''source "$LIB_DOWNLOADS_MODULE"'\'' ./lib.sh
    grep -q '\''source "$LIB_CONFIG_LOADING_MODULE"'\'' ./lib.sh
    grep -q '\''source "$LIB_PATH_SAFETY_MODULE"'\'' ./lib.sh
    grep -q '\''source "$LIB_RUNTIME_INPUTS_MODULE"'\'' ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "dead-function checker ignores comment and string mentions" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/lib.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
alive_fn() { :; }
dead_fn() { :; }
alive_fn
echo "dead_fn appears in string"
# dead_fn appears in comment
EOF

    if (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1); then
      echo "unexpected-success"
      cat "$tmp/out.txt"
      exit 1
    fi

    if ! grep -q "dead-function-check: found functions without call sites" "$tmp/out.txt"; then
      echo "missing-error-marker"
      cat "$tmp/out.txt"
      exit 1
    fi
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dead-function checker accepts real shell call sites" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/lib.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
alive_fn() { :; }
dead_fn() { :; }
alive_fn
dead_fn
EOF

    (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1)
    grep -q "dead-function-check: ok" "$tmp/out.txt"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dead-function checker catches unused helper inside modules health" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh lib.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/modules/health/self_check.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
health_live() { :; }
health_dead() { :; }
health_live
EOF

    if (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1); then
      echo "unexpected-success"
      cat "$tmp/out.txt"
      exit 1
    fi

    grep -q "health_dead" "$tmp/out.txt"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dead-function checker accepts live helper inside modules health" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh lib.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/modules/health/self_check.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
health_live() { :; }
health_bridge() { health_live; }
health_bridge
EOF

    (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1)
    grep -q "dead-function-check: ok" "$tmp/out.txt"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dead-function checker catches unused helper inside modules export" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh lib.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/modules/export/capabilities.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
export_live() { :; }
export_dead() { :; }
export_live
EOF

    if (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1); then
      echo "unexpected-success"
      cat "$tmp/out.txt"
      exit 1
    fi

    grep -q "export_dead" "$tmp/out.txt"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dead-function checker accepts live helper inside modules export" {
    run bash -eo pipefail -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/scripts" "$tmp/modules/lib" "$tmp/modules/config" "$tmp/modules/install" "$tmp/modules/health" "$tmp/modules/export"

    cp ./scripts/check-dead-functions.sh "$tmp/scripts/check-dead-functions.sh"
    chmod +x "$tmp/scripts/check-dead-functions.sh"

    for f in xray-reality.sh install.sh config.sh service.sh health.sh export.sh lib.sh; do
      cat > "$tmp/$f" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
:
EOF
    done

    cat > "$tmp/modules/export/capabilities.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
export_live() { :; }
export_bridge() { export_live; }
export_bridge
EOF

    (cd "$tmp/scripts" && bash ./check-dead-functions.sh > "$tmp/out.txt" 2>&1)
    grep -q "dead-function-check: ok" "$tmp/out.txt"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "dockerfile runs non-root and uses executable healthcheck" {
    run bash -eo pipefail -c '
    grep -Eq '\''^FROM debian:bookworm-[0-9]+-slim(@sha256:[a-f0-9]{64})?$'\'' ./Dockerfile
    grep -q '\''^HEALTHCHECK '\'' ./Dockerfile
    grep -Fq "xray-reality.sh help >/dev/null 2>&1" ./Dockerfile
    grep -q '\''^USER xray$'\'' ./Dockerfile
    grep -q '\''logrotate'\'' ./Dockerfile
    grep -q '\''unzip'\'' ./Dockerfile
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "docs describe strongest-direct dns as ipv4-first policy" {
    run bash -eo pipefail -c '
    grep -Fq "queryStrategy: UseIPv4" ./README.md
    grep -Fq "queryStrategy: UseIPv4" ./README.ru.md
    grep -Fq "server-side DNS remains intentionally IPv4-first" ./docs/en/OPERATIONS.md
    grep -Fq "server-side DNS здесь намеренно остаётся IPv4-first" ./docs/ru/OPERATIONS.md
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "uninstall_flow exits early when managed artifacts are already absent" {
    run bash -eo pipefail -c '
    grep -q '\''if ! uninstall_has_managed_artifacts; then'\'' ./install.sh
    grep -q '\''управляемые артефакты не обнаружены'\'' ./install.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "service sources dedicated uninstall module" {
    run bash -eo pipefail -c '
    grep -Fq '\''SERVICE_UNINSTALL_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/service/uninstall.sh"'\'' ./service.sh
    grep -Fq '\''source "$SERVICE_UNINSTALL_MODULE"'\'' ./service.sh
    grep -q '\''uninstall_all() {'\'' ./modules/service/uninstall.sh
    grep -q '\''uninstall_has_managed_artifacts() {'\'' ./modules/service/uninstall.sh
    grep -Fq '\''systemctl_uninstall_bounded reset-failed xray.service xray-health.service xray-health.timer xray-auto-update.service xray-auto-update.timer'\'' ./modules/service/uninstall.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "service sources dedicated runtime module" {
    run bash -eo pipefail -c '
    grep -Fq '\''SERVICE_RUNTIME_MODULE="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}/modules/service/runtime.sh"'\'' ./service.sh
    grep -Fq '\''source "$SERVICE_RUNTIME_MODULE"'\'' ./service.sh
    grep -q '\''create_systemd_service() {'\'' ./modules/service/runtime.sh
    grep -q '\''start_services() {'\'' ./modules/service/runtime.sh
    grep -q '\''update_xray() {'\'' ./modules/service/runtime.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "uninstall_remove_user_account retries until user disappears" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    source ./service.sh

    id_calls=0
    userdel_calls=0
    id() {
      if [[ "${1:-}" != "xray" ]]; then
        return 1
      fi
      id_calls=$((id_calls + 1))
      if ((id_calls < 4)); then
        return 0
      fi
      return 1
    }
    loginctl() { :; }
    pkill() { :; }
    pgrep() { return 1; }
    userdel() {
      userdel_calls=$((userdel_calls + 1))
      return 0
    }

    uninstall_remove_user_account xray
    ((userdel_calls >= 1))
    ((id_calls >= 4))
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "uninstall_remove_group_account retries until group disappears" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    source ./service.sh

    group_calls=0
    groupdel_calls=0
    getent() {
      if [[ "${1:-}" != "group" || "${2:-}" != "xray" ]]; then
        return 1
      fi
      group_calls=$((group_calls + 1))
      if ((group_calls < 3)); then
        return 0
      fi
      return 1
    }
    groupdel() {
      groupdel_calls=$((groupdel_calls + 1))
      return 0
    }

    uninstall_remove_group_account xray
    ((groupdel_calls == 1))
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rotate_backups safely handles backup directories with spaces" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    XRAY_BACKUP="$(mktemp -d)"
    MAX_BACKUPS=1
    mkdir -p "$XRAY_BACKUP/old backup"
    mkdir -p "$XRAY_BACKUP/new backup"
    touch -d "2020-01-01 00:00:00" "$XRAY_BACKUP/old backup"
    touch -d "2030-01-01 00:00:00" "$XRAY_BACKUP/new backup"
    rotate_backups
    [[ ! -d "$XRAY_BACKUP/old backup" ]]
    [[ -d "$XRAY_BACKUP/new backup" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "rotate_backups falls back to default when MAX_BACKUPS is invalid" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    XRAY_BACKUP="$(mktemp -d)"
    MAX_BACKUPS="abc"
    mkdir -p "$XRAY_BACKUP/older"
    mkdir -p "$XRAY_BACKUP/newer"
    touch -d "2020-01-01 00:00:00" "$XRAY_BACKUP/older"
    touch -d "2030-01-01 00:00:00" "$XRAY_BACKUP/newer"
    rotate_backups
    [[ -d "$XRAY_BACKUP/older" ]]
    [[ -d "$XRAY_BACKUP/newer" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "assign_latest_backup_dir preserves full path with spaces" {
    run bash -eo pipefail -c '
    set -euo pipefail
    source ./lib.sh
    source ./service.sh
    XRAY_BACKUP="$(mktemp -d)"
    mkdir -p "$XRAY_BACKUP/older session"
    mkdir -p "$XRAY_BACKUP/latest session"
    touch -d "2020-01-01 00:00:00" "$XRAY_BACKUP/older session"
    touch -d "2030-01-01 00:00:00" "$XRAY_BACKUP/latest session"
    assign_latest_backup_dir latest_path
    [[ "$latest_path" == "$XRAY_BACKUP/latest session" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
