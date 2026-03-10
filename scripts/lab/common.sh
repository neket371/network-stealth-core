#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

lab_default_host_root() {
    if [[ -n "${LAB_HOST_ROOT:-}" ]]; then
        printf '%s\n' "$LAB_HOST_ROOT"
        return 0
    fi

    if [[ -n "${TMPDIR:-}" && -d "${TMPDIR:-}" && -w "${TMPDIR:-}" ]]; then
        printf '%s/network-stealth-core-lab\n' "$TMPDIR"
        return 0
    fi

    if [[ -d /var/tmp && -w /var/tmp ]]; then
        printf '%s\n' "/var/tmp/network-stealth-core-lab"
        return 0
    fi

    printf '%s\n' "${HOME}/.cache/network-stealth-core-lab"
}

lab_host_root() {
    printf '%s\n' "$(lab_default_host_root)"
}

lab_workspace_dir() {
    printf '%s/workspace\n' "$(lab_host_root)"
}

lab_logs_dir() {
    printf '%s/logs\n' "$(lab_host_root)"
}

lab_artifacts_dir() {
    printf '%s/artifacts\n' "$(lab_host_root)"
}

lab_vm_root_dir() {
    printf '%s/vm\n' "$(lab_host_root)"
}

lab_vm_images_dir() {
    printf '%s/images\n' "$(lab_vm_root_dir)"
}

lab_vm_state_dir() {
    printf '%s/state\n' "$(lab_vm_root_dir)"
}

lab_vm_logs_dir() {
    printf '%s/logs\n' "$(lab_vm_root_dir)"
}

lab_vm_artifacts_dir() {
    printf '%s/artifacts\n' "$(lab_vm_root_dir)"
}

lab_vm_workspace_dir() {
    printf '%s/workspace\n' "$(lab_vm_root_dir)"
}

lab_container_name() {
    printf '%s\n' "${LAB_CONTAINER_NAME:-nsc-lab-2404}"
}

lab_container_image() {
    printf '%s\n' "${LAB_IMAGE:-ubuntu:24.04}"
}

lab_vm_name() {
    printf '%s\n' "${LAB_VM_NAME:-nsc-vm-2404}"
}

lab_vm_guest_user() {
    printf '%s\n' "${LAB_VM_GUEST_USER:-nscvm}"
}

lab_vm_ssh_port() {
    printf '%s\n' "${LAB_VM_SSH_PORT:-10022}"
}

lab_vm_memory_mb() {
    printf '%s\n' "${LAB_VM_MEMORY_MB:-2048}"
}

lab_vm_cpus() {
    printf '%s\n' "${LAB_VM_CPUS:-2}"
}

lab_vm_disk_size() {
    printf '%s\n' "${LAB_VM_DISK_SIZE:-24G}"
}

lab_vm_guest_ipv4() {
    printf '%s\n' "${LAB_VM_GUEST_IPV4:-10.0.2.15}"
}

lab_vm_base_image_url() {
    printf '%s\n' "${LAB_VM_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
}

lab_vm_base_image_path() {
    printf '%s/noble-server-cloudimg-amd64.img\n' "$(lab_vm_images_dir)"
}

lab_vm_overlay_path() {
    printf '%s/%s-overlay.qcow2\n' "$(lab_vm_state_dir)" "$(lab_vm_name)"
}

lab_vm_seed_iso_path() {
    printf '%s/%s-seed.iso\n' "$(lab_vm_state_dir)" "$(lab_vm_name)"
}

lab_vm_user_data_path() {
    printf '%s/%s-user-data.yaml\n' "$(lab_vm_state_dir)" "$(lab_vm_name)"
}

lab_vm_meta_data_path() {
    printf '%s/%s-meta-data.yaml\n' "$(lab_vm_state_dir)" "$(lab_vm_name)"
}

lab_vm_pid_file() {
    printf '%s/%s.pid\n' "$(lab_vm_state_dir)" "$(lab_vm_name)"
}

lab_vm_serial_log() {
    printf '%s/%s-console.log\n' "$(lab_vm_logs_dir)" "$(lab_vm_name)"
}

lab_vm_host_key_file() {
    printf '%s/known_hosts\n' "$(lab_vm_workspace_dir)"
}

lab_vm_ssh_key_path() {
    printf '%s/lab-vm.id_ed25519\n' "$(lab_vm_workspace_dir)"
}

lab_prepare_dirs() {
    mkdir -p "$(lab_workspace_dir)" "$(lab_logs_dir)" "$(lab_artifacts_dir)"
}

lab_prepare_vm_dirs() {
    mkdir -p \
        "$(lab_vm_root_dir)" \
        "$(lab_vm_images_dir)" \
        "$(lab_vm_state_dir)" \
        "$(lab_vm_logs_dir)" \
        "$(lab_vm_artifacts_dir)" \
        "$(lab_vm_workspace_dir)"
}

lab_detect_runtime() {
    if [[ -n "${LAB_RUNTIME:-}" && "${LAB_RUNTIME}" != "auto" ]]; then
        if ! command -v "$LAB_RUNTIME" > /dev/null 2>&1; then
            echo "requested runtime not found: ${LAB_RUNTIME}" >&2
            return 1
        fi
        printf '%s\n' "$LAB_RUNTIME"
        return 0
    fi

    if command -v docker > /dev/null 2>&1; then
        printf '%s\n' "docker"
        return 0
    fi
    if command -v podman > /dev/null 2>&1; then
        printf '%s\n' "podman"
        return 0
    fi

    echo "no supported container runtime found (need docker or podman)" >&2
    return 1
}

LAB_RUNTIME_BIN=""
LAB_RUNTIME_PREFIX=()

lab_resolve_runtime_access() {
    LAB_RUNTIME_BIN="$(lab_detect_runtime)"
    LAB_RUNTIME_PREFIX=()

    if "$LAB_RUNTIME_BIN" info > /dev/null 2>&1; then
        return 0
    fi

    if command -v sudo > /dev/null 2>&1 && sudo -n "$LAB_RUNTIME_BIN" info > /dev/null 2>&1; then
        LAB_RUNTIME_PREFIX=(sudo -n)
        return 0
    fi

    echo "runtime '${LAB_RUNTIME_BIN}' is present but not accessible; add runner user to the runtime group or allow passwordless sudo" >&2
    return 1
}

lab_runtime() {
    if [[ -z "$LAB_RUNTIME_BIN" ]]; then
        lab_resolve_runtime_access
    fi
    "${LAB_RUNTIME_PREFIX[@]}" "$LAB_RUNTIME_BIN" "$@"
}

lab_remove_container_if_present() {
    local name
    name="$(lab_container_name)"
    if lab_runtime ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
        lab_runtime rm -f "$name" > /dev/null 2>&1 || true
    fi
}

lab_timestamp() {
    date -u '+%Y%m%dT%H%M%SZ'
}

lab_write_env_file() {
    local env_file="$1"
    cat > "$env_file" << EOF
LAB_HOST_ROOT=$(lab_host_root)
LAB_WORKSPACE_DIR=$(lab_workspace_dir)
LAB_LOGS_DIR=$(lab_logs_dir)
LAB_ARTIFACTS_DIR=$(lab_artifacts_dir)
LAB_CONTAINER_NAME=$(lab_container_name)
LAB_IMAGE=$(lab_container_image)
LAB_RUNTIME=${LAB_RUNTIME_BIN}
LAB_REPO_ROOT=${LAB_ROOT_DIR}
EOF
}

lab_write_vm_env_file() {
    local env_file="$1"
    cat > "$env_file" << EOF
LAB_HOST_ROOT=$(lab_host_root)
LAB_VM_ROOT_DIR=$(lab_vm_root_dir)
LAB_VM_IMAGES_DIR=$(lab_vm_images_dir)
LAB_VM_STATE_DIR=$(lab_vm_state_dir)
LAB_VM_LOGS_DIR=$(lab_vm_logs_dir)
LAB_VM_ARTIFACTS_DIR=$(lab_vm_artifacts_dir)
LAB_VM_WORKSPACE_DIR=$(lab_vm_workspace_dir)
LAB_VM_NAME=$(lab_vm_name)
LAB_VM_GUEST_USER=$(lab_vm_guest_user)
LAB_VM_SSH_PORT=$(lab_vm_ssh_port)
LAB_VM_MEMORY_MB=$(lab_vm_memory_mb)
LAB_VM_CPUS=$(lab_vm_cpus)
LAB_VM_DISK_SIZE=$(lab_vm_disk_size)
LAB_VM_GUEST_IPV4=$(lab_vm_guest_ipv4)
LAB_VM_BASE_IMAGE_URL=$(lab_vm_base_image_url)
LAB_VM_BASE_IMAGE_PATH=$(lab_vm_base_image_path)
LAB_VM_OVERLAY_PATH=$(lab_vm_overlay_path)
LAB_VM_SEED_ISO_PATH=$(lab_vm_seed_iso_path)
LAB_VM_USER_DATA_PATH=$(lab_vm_user_data_path)
LAB_VM_META_DATA_PATH=$(lab_vm_meta_data_path)
LAB_VM_PID_FILE=$(lab_vm_pid_file)
LAB_VM_SERIAL_LOG=$(lab_vm_serial_log)
LAB_VM_HOST_KEY_FILE=$(lab_vm_host_key_file)
LAB_VM_SSH_KEY_PATH=$(lab_vm_ssh_key_path)
LAB_REPO_ROOT=${LAB_ROOT_DIR}
EOF
}
