#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/enter-vm-smoke.sh [ssh-args...]
EOF
}

case "${1:-}" in
    --help | -h)
        usage
        exit 0
        ;;
    *) ;;
esac

latest_env="$(lab_vm_workspace_dir)/latest-vm-run.env"
if [[ -f "$latest_env" ]]; then
    # shellcheck disable=SC1090
    source "$latest_env"
fi

ssh_key="$(lab_vm_ssh_key_path)"
host_key_file="$(lab_vm_host_key_file)"
ssh_port="$(lab_vm_ssh_port)"
guest_user="$(lab_vm_guest_user)"

if [[ -t 1 ]]; then
    cat << 'EOF'
vm-lab tip:
  используй nsc-vm-install-latest [--num-configs n|--advanced]
  или nsc-vm-install-repo [--num-configs n|--advanced]
  raw curl install внутри гостя может автоопределить public ip хоста и завалить self-check.

EOF
fi

exec ssh \
    -i "$ssh_key" \
    -o UserKnownHostsFile="$host_key_file" \
    -o StrictHostKeyChecking=accept-new \
    -o LogLevel=ERROR \
    -p "$ssh_port" \
    "${guest_user}@127.0.0.1" \
    "$@"
