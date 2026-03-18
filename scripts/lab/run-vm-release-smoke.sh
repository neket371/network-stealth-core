#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << 'EOF'
usage:
  RELEASE_TAG=vX.Y.Z bash scripts/lab/run-vm-release-smoke.sh

environment:
  RELEASE_TAG               required release tag or version (for example: vX.Y.Z or X.Y.Z)
  LAB_HOST_ROOT             host directory for vm-lab state
  LAB_VM_KEEP_RUNNING       keep vm up after smoke (default: false)
  START_PORT                guest start port for release install (default: 24440)
  INITIAL_CONFIGS           initial config count for release install (default: 1)
  ADD_CONFIGS               add-clients count after install (default: 1)
  E2E_ALLOW_INSECURE_SHA256 true|false (default: true)
  XRAY_CUSTOM_DOMAINS       deterministic vm-lab domains (default: vk.com,yoomoney.ru,cdek.ru)
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

if [[ -z "${RELEASE_TAG:-}" ]]; then
    echo "RELEASE_TAG is required" >&2
    usage >&2
    exit 1
fi

exec env VM_GUEST_MODE=release RELEASE_TAG="${RELEASE_TAG}" bash "${SCRIPT_DIR}/run-vm-lifecycle-smoke.sh"
