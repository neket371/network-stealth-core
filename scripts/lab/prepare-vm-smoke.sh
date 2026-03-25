#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/prepare-vm-smoke.sh

environment:
  LAB_HOST_ROOT             host directory for vm-lab state
  LAB_VM_AUTO_INSTALL_DEPS  true|false (default: false)
  LAB_VM_NAME               vm name (default: nsc-vm-2404)
  LAB_VM_GUEST_USER         guest ssh user (default: nscvm)
  LAB_VM_SSH_PORT           host loopback ssh port (default: 10022)
  LAB_VM_MEMORY_MB          vm memory in mb (default: 2048)
  LAB_VM_CPUS               vm vcpu count (default: 2)
  LAB_VM_DISK_SIZE          qcow2 overlay size (default: 24G)
  LAB_VM_BASE_IMAGE_URL     ubuntu cloud image url
EOF
}

prepare_vm_validate_args() {
    case "${1:-}" in
        --help | -h)
            usage
            exit 0
            ;;
        "") ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
}

install_missing_deps() {
    [[ "${LAB_VM_AUTO_INSTALL_DEPS:-false}" == "true" ]] || return 0
    if ! command -v apt-get > /dev/null 2>&1; then
        echo "auto-install is only supported on apt-based hosts" >&2
        return 1
    fi

    local -a missing=()
    local cmd
    for cmd in curl qemu-system-x86_64 qemu-img cloud-localds ssh ssh-keygen; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            case "$cmd" in
                qemu-system-x86_64) missing+=(qemu-system-x86) ;;
                qemu-img) missing+=(qemu-utils) ;;
                cloud-localds) missing+=(cloud-image-utils) ;;
                ssh | ssh-keygen) missing+=(openssh-client) ;;
                *) missing+=("$cmd") ;;
            esac
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    local -a unique=()
    local pkg
    for pkg in "${missing[@]}"; do
        if [[ " ${unique[*]} " != *" ${pkg} "* ]]; then
            unique+=("$pkg")
        fi
    done

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        apt-get update -qq
        apt-get install -y "${unique[@]}"
    elif command -v sudo > /dev/null 2>&1 && sudo -n true 2> /dev/null; then
        sudo -n apt-get update -qq
        sudo -n apt-get install -y "${unique[@]}"
    else
        echo "vm deps are missing and automatic install needs root or passwordless sudo" >&2
        return 1
    fi
}

require_vm_dependency() {
    local cmd="$1"
    command -v "$cmd" > /dev/null 2>&1 || {
        echo "required command not found: ${cmd}" >&2
        exit 1
    }
}

prepare_vm_base_image() {
    local base_image
    local base_image_url
    local tmp_image

    base_image="$(lab_vm_base_image_path)"
    base_image_url="$(lab_vm_base_image_url)"
    tmp_image="${base_image}.part"

    mkdir -p "$(dirname "$base_image")"
    rm -f "$tmp_image"

    if [[ -f "$base_image" ]]; then
        printf '%s\n' "$base_image"
        return 0
    fi

    if ! curl --fail --location --show-error --silent "$base_image_url" -o "$tmp_image"; then
        rm -f "$tmp_image"
        return 1
    fi

    if [[ ! -s "$tmp_image" ]]; then
        echo "downloaded vm base image temp file is missing or empty: ${tmp_image}" >&2
        rm -f "$tmp_image"
        return 1
    fi

    if ! mv -f "$tmp_image" "$base_image"; then
        rm -f "$tmp_image"
        return 1
    fi

    printf '%s\n' "$base_image"
}

prepare_vm_smoke_main() {
    local ssh_key
    local base_image
    local env_file

    prepare_vm_validate_args "${1:-}"

    lab_prepare_dirs
    lab_prepare_vm_dirs
    install_missing_deps

    require_vm_dependency curl
    require_vm_dependency qemu-system-x86_64
    require_vm_dependency qemu-img
    require_vm_dependency cloud-localds
    require_vm_dependency ssh
    require_vm_dependency ssh-keygen

    if [[ ! -c /dev/kvm ]]; then
        echo "/dev/kvm is not available; vm-lab requires kvm for safe full lifecycle smoke" >&2
        exit 1
    fi

    ssh_key="$(lab_vm_ssh_key_path)"
    if [[ ! -f "$ssh_key" ]]; then
        ssh-keygen -q -t ed25519 -N "" -f "$ssh_key" > /dev/null
    fi

    base_image="$(prepare_vm_base_image)"

    env_file="$(lab_vm_workspace_dir)/lab-vm-env.sh"
    lab_write_vm_env_file "$env_file"

    cat << EOF
vm host root: $(lab_vm_root_dir)
vm name: $(lab_vm_name)
guest user: $(lab_vm_guest_user)
ssh port: $(lab_vm_ssh_port)
base image: ${base_image}
ssh key: ${ssh_key}
env file: ${env_file}
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    prepare_vm_smoke_main "$@"
fi
