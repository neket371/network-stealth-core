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

lab_container_name() {
    printf '%s\n' "${LAB_CONTAINER_NAME:-nsc-lab-2404}"
}

lab_container_image() {
    printf '%s\n' "${LAB_IMAGE:-ubuntu:24.04}"
}

lab_prepare_dirs() {
    mkdir -p "$(lab_workspace_dir)" "$(lab_logs_dir)" "$(lab_artifacts_dir)"
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
