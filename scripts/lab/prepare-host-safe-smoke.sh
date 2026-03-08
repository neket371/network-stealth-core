#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/prepare-host-safe-smoke.sh

environment:
  LAB_RUNTIME         docker|podman|auto (default: auto)
  LAB_HOST_ROOT       host directory for workspace/logs/artifacts
  LAB_CONTAINER_NAME  container name (default: nsc-lab-2404)
  LAB_IMAGE           container image (default: ubuntu:24.04)
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

lab_prepare_dirs
lab_resolve_runtime_access

env_file="$(lab_workspace_dir)/lab-env.sh"
lab_write_env_file "$env_file"

cat << EOF
host root: $(lab_host_root)
runtime: ${LAB_RUNTIME_BIN}
container: $(lab_container_name)
image: $(lab_container_image)
env file: ${env_file}
EOF
