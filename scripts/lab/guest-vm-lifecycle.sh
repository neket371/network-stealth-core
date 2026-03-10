#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

guest_primary_ipv4() {
    local ip
    ip="$(ip -4 route get 1.1.1.1 2> /dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return 0
    fi
    ip="$(ip -4 -o addr show scope global 2> /dev/null | awk '{split($4, a, "/"); print a[1]; exit}')"
    [[ -n "$ip" ]] || return 1
    printf '%s\n' "$ip"
}

install_guest_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        bash \
        ca-certificates \
        curl \
        expect \
        iproute2 \
        jq \
        logrotate \
        openssh-client \
        openssl \
        procps \
        python3 \
        unzip \
        uuid-runtime > /dev/null
}

resolve_latest_stable_xray_version() {
    local api_url="${XRAY_RELEASES_API:-https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5}"
    local releases_json latest_tag

    releases_json="$(curl --fail --show-error --silent --location "$api_url" 2> /dev/null || true)"
    [[ -n "$releases_json" ]] || return 1

    latest_tag="$(jq -r '[.[] | select((.draft | not) and (.prerelease | not))][0].tag_name // empty' <<< "$releases_json" | sed 's/^v//')"
    [[ -n "$latest_tag" ]] || return 1
    printf '%s\n' "$latest_tag"
}

main() {
    install_guest_dependencies

    local guest_ip
    guest_ip="$(guest_primary_ipv4)"
    [[ -n "$guest_ip" ]] || {
        echo "failed to detect guest ipv4" >&2
        exit 1
    }

    local resolved_version=""
    if [[ -z "${INSTALL_VERSION:-}" || -z "${UPDATE_VERSION:-}" ]]; then
        resolved_version="$(resolve_latest_stable_xray_version || true)"
    fi
    if [[ -z "${INSTALL_VERSION:-}" && -n "$resolved_version" ]]; then
        INSTALL_VERSION="$resolved_version"
    fi
    if [[ -z "${UPDATE_VERSION:-}" && -n "${INSTALL_VERSION:-}" ]]; then
        UPDATE_VERSION="$INSTALL_VERSION"
    fi

    local -a env_args=(
        START_PORT="${START_PORT:-24440}"
        INITIAL_CONFIGS="${INITIAL_CONFIGS:-1}"
        ADD_CONFIGS="${ADD_CONFIGS:-1}"
        E2E_SERVER_IP="${E2E_SERVER_IP:-$guest_ip}"
        E2E_DOMAIN_CHECK="${E2E_DOMAIN_CHECK:-false}"
        E2E_SKIP_REALITY_CHECK="${E2E_SKIP_REALITY_CHECK:-false}"
        E2E_ALLOW_INSECURE_SHA256="${E2E_ALLOW_INSECURE_SHA256:-true}"
        XRAY_CUSTOM_DOMAINS="${XRAY_CUSTOM_DOMAINS:-vk.com,yoomoney.ru,cdek.ru}"
    )

    if [[ -n "${INSTALL_VERSION:-}" ]]; then
        env_args+=(INSTALL_VERSION="${INSTALL_VERSION}")
    fi
    if [[ -n "${UPDATE_VERSION:-}" ]]; then
        env_args+=(UPDATE_VERSION="${UPDATE_VERSION}")
    fi

    sudo env "${env_args[@]}" bash "${ROOT_DIR}/tests/e2e/nightly_smoke_install_add_update_uninstall.sh"
}

main "$@"
