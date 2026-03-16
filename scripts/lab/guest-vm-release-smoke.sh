#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/xray-reality.sh"
XRAY_MANAGED_CUSTOM_DOMAINS_FILE="${XRAY_MANAGED_CUSTOM_DOMAINS_FILE:-/etc/xray-reality/custom-domains.txt}"
RELEASE_TAG="${RELEASE_TAG:-}"
INITIAL_CONFIGS="${INITIAL_CONFIGS:-1}"
ADD_CONFIGS="${ADD_CONFIGS:-1}"
E2E_KEEP_FAILURE_STATE="${E2E_KEEP_FAILURE_STATE:-false}"
E2E_PROOF_DIR="${E2E_PROOF_DIR:-$HOME/vm-proof}"
declare -a RELEASE_STEPS=()

# shellcheck source=tests/e2e/lib.sh
source "$ROOT_DIR/tests/e2e/lib.sh"
# shellcheck source=scripts/lab/guest-vm-lifecycle.sh
source "$ROOT_DIR/scripts/lab/guest-vm-lifecycle.sh"

release_smoke_record_step() {
    RELEASE_STEPS+=("$1")
}

release_smoke_capture_optional_file() {
    local src="$1"
    local dst="$2"
    if run_root test -f "$src"; then
        run_root cat "$src" > "$dst"
    fi
}

release_smoke_write_manifest() {
    local manifest="${E2E_PROOF_DIR}/release-bootstrap-lifecycle.txt"
    {
        printf 'release_tag=%s\n' "$RELEASE_TAG"
        printf 'initial_configs=%s\n' "$INITIAL_CONFIGS"
        printf 'add_configs=%s\n' "$ADD_CONFIGS"
        printf 'steps=%s\n' "${RELEASE_STEPS[*]}"
    } > "$manifest"
}

release_smoke_capture_failure() {
    mkdir -p "$E2E_PROOF_DIR"
    run_root systemctl status xray --no-pager -l > "${E2E_PROOF_DIR}/failure-systemctl-status-xray.txt" 2>&1 || true
    run_root journalctl -u xray --no-pager -n 200 > "${E2E_PROOF_DIR}/failure-journal-xray.txt" 2>&1 || true
    run_root journalctl -u xray-health --no-pager -n 200 > "${E2E_PROOF_DIR}/failure-journal-xray-health.txt" 2>&1 || true
    release_smoke_capture_optional_file "/etc/xray-reality/config.env" "${E2E_PROOF_DIR}/failure-config.env"
    release_smoke_capture_optional_file "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE" "${E2E_PROOF_DIR}/failure-custom-domains.txt"
}

release_smoke_cleanup_state() {
    cleanup_installation "$SCRIPT_PATH"
}

release_smoke_cleanup_on_exit() {
    local exit_code=$?
    if ((exit_code != 0)); then
        release_smoke_capture_failure || true
    fi
    if ((exit_code != 0)) && [[ "$E2E_KEEP_FAILURE_STATE" == "true" ]]; then
        echo "==> keeping failed release bootstrap state for inspection"
        return 0
    fi
    release_smoke_cleanup_state
}

assert_custom_domains_persisted() {
    local domain
    local -a expected_domains=()

    if [[ -z "${XRAY_CUSTOM_DOMAINS:-}" ]]; then
        XRAY_CUSTOM_DOMAINS="$(vm_lab_default_custom_domains)"
    fi

    assert_path_mode_owner "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE" root root 600

    if ! run_root grep -Fqx "XRAY_DOMAINS_FILE=${XRAY_MANAGED_CUSTOM_DOMAINS_FILE}" /etc/xray-reality/config.env; then
        echo "managed XRAY_DOMAINS_FILE is not persisted in /etc/xray-reality/config.env" >&2
        run_root cat /etc/xray-reality/config.env >&2 || true
        exit 1
    fi

    IFS=',' read -r -a expected_domains <<< "${XRAY_CUSTOM_DOMAINS}"
    for domain in "${expected_domains[@]}"; do
        domain="${domain//[[:space:]]/}"
        [[ -n "$domain" ]] || continue
        if ! run_root grep -Fqx "$domain" "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE"; then
            echo "managed custom domains file is missing expected domain: ${domain}" >&2
            run_root cat "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE" >&2 || true
            exit 1
        fi
    done
}

main() {
    [[ -n "$RELEASE_TAG" ]] || {
        echo "RELEASE_TAG is required" >&2
        exit 1
    }

    mkdir -p "$E2E_PROOF_DIR"
    release_smoke_cleanup_state

    install_guest_dependencies
    wait_for_systemd_settle
    install_guest_manual_helpers

    echo "==> release bootstrap install (${RELEASE_TAG})"
    run_root nsc-vm-install-release "$RELEASE_TAG" --num-configs "$INITIAL_CONFIGS" > "${E2E_PROOF_DIR}/install.txt"
    release_smoke_record_step install
    assert_service_active xray
    assert_xray_runtime_logs_contract
    assert_custom_domains_persisted

    echo "==> add-clients via persisted custom domains"
    run_root bash "$SCRIPT_PATH" add-clients "$ADD_CONFIGS" > "${E2E_PROOF_DIR}/add-clients.txt"
    release_smoke_record_step add-clients
    assert_service_active xray
    assert_custom_domains_persisted

    echo "==> repair"
    run_root bash "$SCRIPT_PATH" repair > "${E2E_PROOF_DIR}/repair.txt"
    release_smoke_record_step repair
    assert_service_active xray
    assert_custom_domains_persisted

    echo "==> status --verbose"
    run_root bash "$SCRIPT_PATH" status --verbose > "${E2E_PROOF_DIR}/status-verbose.txt"
    release_smoke_record_step status

    echo "==> check-update"
    run_root bash "$SCRIPT_PATH" check-update > "${E2E_PROOF_DIR}/check-update.txt"
    release_smoke_record_step check-update

    echo "==> diagnose"
    run_root bash "$SCRIPT_PATH" diagnose > "${E2E_PROOF_DIR}/diagnose.txt" || true
    release_smoke_record_step diagnose

    release_smoke_capture_optional_file "/etc/xray-reality/config.env" "${E2E_PROOF_DIR}/config.env"
    release_smoke_capture_optional_file "$XRAY_MANAGED_CUSTOM_DOMAINS_FILE" "${E2E_PROOF_DIR}/custom-domains.txt"
    release_smoke_write_manifest

    echo "==> uninstall"
    run_root bash "$SCRIPT_PATH" uninstall --yes --non-interactive > "${E2E_PROOF_DIR}/uninstall.txt"
    release_smoke_record_step uninstall
    assert_path_absent "/etc/xray-reality"
    release_smoke_write_manifest

    echo "release bootstrap vm smoke: ok"
}

trap release_smoke_cleanup_on_exit EXIT

main "$@"
