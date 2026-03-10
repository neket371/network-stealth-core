#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/run-vm-lifecycle-smoke.sh

environment:
  LAB_HOST_ROOT             host directory for vm-lab state
  LAB_VM_AUTO_INSTALL_DEPS  true|false (default: false)
  LAB_VM_NAME               vm name (default: nsc-vm-2404)
  LAB_VM_GUEST_USER         guest ssh user (default: nscvm)
  LAB_VM_SSH_PORT           host loopback ssh port (default: 10022)
  LAB_VM_MEMORY_MB          vm memory in mb (default: 2048)
  LAB_VM_CPUS               vm vcpu count (default: 2)
  LAB_VM_DISK_SIZE          qcow2 overlay size (default: 24G)
  LAB_VM_KEEP_RUNNING       keep vm up after smoke (default: false)
  START_PORT                guest start port for install (default: 24440)
  INITIAL_CONFIGS           initial config count (default: 1)
  ADD_CONFIGS               add-clients count (default: 1)
  E2E_DOMAIN_CHECK          true|false (default: false)
  E2E_SKIP_REALITY_CHECK    true|false (default: false)
  E2E_ALLOW_INSECURE_SHA256 true|false (default: true)
  E2E_KEEP_FAILURE_STATE    true|false (default: true when LAB_VM_KEEP_RUNNING=true, else false)
  XRAY_CUSTOM_DOMAINS       deterministic vm-lab domains (default: vk.com,yoomoney.ru,cdek.ru)
  INSTALL_VERSION           optional xray version for install
  UPDATE_VERSION            optional xray version for update (default: install version)
EOF
}

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

wait_for_ssh() {
    local attempts="${1:-60}"
    local ssh_key host_key_file guest_user ssh_port
    ssh_key="$(lab_vm_ssh_key_path)"
    host_key_file="$(lab_vm_host_key_file)"
    guest_user="$(lab_vm_guest_user)"
    ssh_port="$(lab_vm_ssh_port)"

    local i
    for ((i = 1; i <= attempts; i++)); do
        if ssh \
            -i "$ssh_key" \
            -o UserKnownHostsFile="$host_key_file" \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=5 \
            -o LogLevel=ERROR \
            -p "$ssh_port" \
            "${guest_user}@127.0.0.1" \
            true > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done

    return 1
}

vm_pid_running() {
    local pid_file pid
    pid_file="$(lab_vm_pid_file)"
    [[ -f "$pid_file" ]] || return 1
    pid="$(< "$pid_file")"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2> /dev/null
}

stop_vm_if_running() {
    local pid_file pid
    pid_file="$(lab_vm_pid_file)"
    if ! vm_pid_running; then
        rm -f "$pid_file"
        return 0
    fi

    pid="$(< "$pid_file")"
    kill "$pid" 2> /dev/null || true

    local i
    for ((i = 1; i <= 20; i++)); do
        if ! kill -0 "$pid" 2> /dev/null; then
            break
        fi
        sleep 1
    done

    if kill -0 "$pid" 2> /dev/null; then
        kill -9 "$pid" 2> /dev/null || true
    fi

    rm -f "$pid_file"
}

copy_repo_to_guest() {
    local ssh_key host_key_file guest_user ssh_port
    ssh_key="$(lab_vm_ssh_key_path)"
    host_key_file="$(lab_vm_host_key_file)"
    guest_user="$(lab_vm_guest_user)"
    ssh_port="$(lab_vm_ssh_port)"

    tar --exclude='.git' -C "$LAB_ROOT_DIR" -cf - . | ssh \
        -i "$ssh_key" \
        -o UserKnownHostsFile="$host_key_file" \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -p "$ssh_port" \
        "${guest_user}@127.0.0.1" \
        'rm -rf ~/repo && mkdir -p ~/repo && tar -xf - -C ~/repo'
}

collect_guest_logs() {
    local timestamp="$1"
    local ssh_key host_key_file guest_user ssh_port
    ssh_key="$(lab_vm_ssh_key_path)"
    host_key_file="$(lab_vm_host_key_file)"
    guest_user="$(lab_vm_guest_user)"
    ssh_port="$(lab_vm_ssh_port)"

    ssh \
        -i "$ssh_key" \
        -o UserKnownHostsFile="$host_key_file" \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -p "$ssh_port" \
        "${guest_user}@127.0.0.1" \
        'sudo cat /var/log/xray-install.log 2>/dev/null || true' > "$(lab_vm_logs_dir)/xray-install-${timestamp}.log" || true

    ssh \
        -i "$ssh_key" \
        -o UserKnownHostsFile="$host_key_file" \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -p "$ssh_port" \
        "${guest_user}@127.0.0.1" \
        'sudo journalctl --no-pager -u xray 2>/dev/null || true' > "$(lab_vm_logs_dir)/journal-xray-${timestamp}.log" || true

    ssh \
        -i "$ssh_key" \
        -o UserKnownHostsFile="$host_key_file" \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -p "$ssh_port" \
        "${guest_user}@127.0.0.1" \
        'sudo journalctl --no-pager -u xray-health 2>/dev/null || true' > "$(lab_vm_logs_dir)/journal-xray-health-${timestamp}.log" || true
}

lab_prepare_dirs
lab_prepare_vm_dirs
bash "$SCRIPT_DIR/prepare-vm-smoke.sh"

timestamp="$(lab_timestamp)"
vm_name="$(lab_vm_name)"
ssh_port="$(lab_vm_ssh_port)"
guest_user="$(lab_vm_guest_user)"
base_image="$(lab_vm_base_image_path)"
overlay_image="$(lab_vm_overlay_path)"
seed_iso="$(lab_vm_seed_iso_path)"
user_data="$(lab_vm_user_data_path)"
meta_data="$(lab_vm_meta_data_path)"
pid_file="$(lab_vm_pid_file)"
serial_log="$(lab_vm_serial_log)"
ssh_key="$(lab_vm_ssh_key_path)"
ssh_pub_key="${ssh_key}.pub"
host_key_file="$(lab_vm_host_key_file)"
keep_running="${LAB_VM_KEEP_RUNNING:-false}"
keep_failure_state="${E2E_KEEP_FAILURE_STATE:-}"
run_log="$(lab_vm_logs_dir)/vm-smoke-${timestamp}.log"
summary_file="$(lab_vm_workspace_dir)/latest-vm-run.env"

if [[ -z "$keep_failure_state" && "$keep_running" == "true" ]]; then
    keep_failure_state="true"
fi
if [[ -z "$keep_failure_state" ]]; then
    keep_failure_state="false"
fi

cleanup_vm() {
    if [[ "$keep_running" == "true" ]]; then
        return 0
    fi
    stop_vm_if_running
    rm -f "$overlay_image" "$seed_iso" "$user_data" "$meta_data"
}
trap cleanup_vm EXIT

stop_vm_if_running
rm -f "$overlay_image" "$seed_iso" "$user_data" "$meta_data"
ssh-keygen -R "[127.0.0.1]:${ssh_port}" -f "$host_key_file" > /dev/null 2>&1 || true

cat > "$user_data" << EOF
#cloud-config
hostname: ${vm_name}
manage_etc_hosts: true
users:
  - default
  - name: ${guest_user}
    gecos: network stealth core vm lab
    shell: /bin/bash
    groups: [adm, sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(< "$ssh_pub_key")
ssh_pwauth: false
package_update: false
package_upgrade: false
EOF

cat > "$meta_data" << EOF
instance-id: ${vm_name}-${timestamp}
local-hostname: ${vm_name}
EOF

cloud-localds "$seed_iso" "$user_data" "$meta_data" > /dev/null
qemu-img create -q -f qcow2 -F qcow2 -b "$base_image" "$overlay_image" "$(lab_vm_disk_size)"

qemu-system-x86_64 \
    -name "$vm_name" \
    -enable-kvm \
    -cpu host \
    -smp "$(lab_vm_cpus)" \
    -m "$(lab_vm_memory_mb)" \
    -display none \
    -daemonize \
    -no-reboot \
    -pidfile "$pid_file" \
    -serial "file:${serial_log}" \
    -drive "file=${overlay_image},if=virtio,format=qcow2" \
    -drive "file=${seed_iso},if=virtio,media=cdrom,format=raw" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${ssh_port}-:22" \
    -device virtio-net-pci,netdev=net0

if ! wait_for_ssh 90; then
    echo "vm ssh did not become ready; inspect ${serial_log}" >&2
    exit 1
fi

copy_repo_to_guest

set +e
ssh \
    -i "$ssh_key" \
    -o UserKnownHostsFile="$host_key_file" \
    -o StrictHostKeyChecking=accept-new \
    -o LogLevel=ERROR \
    -p "$ssh_port" \
    "${guest_user}@127.0.0.1" \
    "cd ~/repo && START_PORT='${START_PORT:-24440}' INITIAL_CONFIGS='${INITIAL_CONFIGS:-1}' ADD_CONFIGS='${ADD_CONFIGS:-1}' E2E_DOMAIN_CHECK='${E2E_DOMAIN_CHECK:-false}' E2E_SKIP_REALITY_CHECK='${E2E_SKIP_REALITY_CHECK:-false}' E2E_ALLOW_INSECURE_SHA256='${E2E_ALLOW_INSECURE_SHA256:-true}' E2E_KEEP_FAILURE_STATE='${keep_failure_state}' XRAY_CUSTOM_DOMAINS='${XRAY_CUSTOM_DOMAINS:-vk.com,yoomoney.ru,cdek.ru}' INSTALL_VERSION='${INSTALL_VERSION:-}' UPDATE_VERSION='${UPDATE_VERSION:-}' bash scripts/lab/guest-vm-lifecycle.sh" | tee "$run_log"
smoke_status=$?
set -e

collect_guest_logs "$timestamp"

cat > "$summary_file" << EOF
LAB_VM_TIMESTAMP=${timestamp}
LAB_VM_NAME=${vm_name}
LAB_VM_SSH_PORT=${ssh_port}
LAB_VM_GUEST_USER=${guest_user}
LAB_VM_GUEST_IP=$(lab_vm_guest_ipv4)
LAB_VM_SMOKE_STATUS=${smoke_status}
LAB_VM_LOG=${run_log}
EOF

result_json="$(bash "$SCRIPT_DIR/collect-vm-artifacts.sh" --timestamp "$timestamp" --guest-ip "$(lab_vm_guest_ipv4)" --smoke-status "$smoke_status")"

if ((smoke_status != 0)); then
    echo "vm lifecycle smoke failed; inspect ${run_log} and ${serial_log}" >&2
    echo "vm summary: ${result_json}" >&2
    exit "$smoke_status"
fi

cat << EOF
vm lab smoke: ok
vm: ${vm_name}
ssh: ${guest_user}@127.0.0.1:${ssh_port}
logs: $(lab_vm_logs_dir)
artifacts: $(lab_vm_artifacts_dir)
summary: ${result_json}
guest tips:
  bash scripts/lab/enter-vm-smoke.sh
  nsc-vm-install-latest --num-configs 3
  nsc-vm-install-repo --advanced
EOF
