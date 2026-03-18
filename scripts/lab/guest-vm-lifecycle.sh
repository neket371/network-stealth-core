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

wait_for_systemd_settle() {
    local attempts=30
    local state=""
    local i

    for ((i = 1; i <= attempts; i++)); do
        state="$(systemctl is-system-running 2> /dev/null || true)"
        case "$state" in
            running | degraded)
                sudo systemctl reset-failed > /dev/null 2>&1 || true
                return 0
                ;;
            *)
                sleep 2
                ;;
        esac
    done

    echo "systemd did not fully settle before vm-lab lifecycle run (state=${state:-unknown}); continuing with best effort" >&2
    sudo systemctl reset-failed > /dev/null 2>&1 || true
    return 0
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

vm_lab_default_custom_domains() {
    printf '%s\n' "${XRAY_CUSTOM_DOMAINS:-vk.com,yoomoney.ru,cdek.ru}"
}

install_guest_manual_helpers() {
    cat > "${HOME}/vm-lab-quickstart.txt" << 'EOF'
vm-lab: быстрый старт
=====================

используй внутри гостя:

  nsc-vm-guest-ip
  nsc-vm-install-latest --num-configs 3
  nsc-vm-install-latest --advanced
  nsc-vm-install-release vX.Y.Z --num-configs 1
  nsc-vm-install-repo --num-configs 3
  nsc-vm-install-repo --advanced

зачем:
- raw curl install внутри этого гостя может автоопределить public ip хоста
  и завалить финальный self-check
- helper-обёртки автоматически фиксируют SERVER_IP на guest ipv4
- для release/bootstrap evidence path используй только nsc-vm-install-release
- release helper по умолчанию фиксирует vm-lab-safe custom domains и start_port
- helper-обёртки для vm-lab по умолчанию разрешают sha256 fallback,
  если upstream релиз xray не содержит minisign-подпись
EOF

    sudo tee /usr/local/bin/nsc-vm-guest-ip > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

guest_ip="$(ip -4 route get 1.1.1.1 2> /dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
if [[ -z "$guest_ip" ]]; then
    guest_ip="$(ip -4 -o addr show scope global 2> /dev/null | awk '{split($4, a, "/"); print a[1]; exit}')"
fi
[[ -n "$guest_ip" ]] || {
    echo "failed to detect guest ipv4" >&2
    exit 1
}
printf '%s\n' "$guest_ip"
EOF
    sudo chmod 0755 /usr/local/bin/nsc-vm-guest-ip

    sudo tee /usr/local/bin/nsc-vm-install-latest > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

guest_ip="${SERVER_IP:-}"
if [[ -z "$guest_ip" ]]; then
    guest_ip="$(nsc-vm-guest-ip)"
fi
allow_insecure_sha256="${ALLOW_INSECURE_SHA256:-true}"

curl -fL https://raw.githubusercontent.com/neket371/network-stealth-core/ubuntu/xray-reality.sh -o /tmp/xray-reality.sh

if [[ "$(id -u)" -eq 0 ]]; then
    exec env SERVER_IP="$guest_ip" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash /tmp/xray-reality.sh install "$@"
fi

exec sudo env SERVER_IP="$guest_ip" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash /tmp/xray-reality.sh install "$@"
EOF
    sudo chmod 0755 /usr/local/bin/nsc-vm-install-latest

    sudo tee /usr/local/bin/nsc-vm-install-release > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

release_ref="${1:-}"
[[ -n "$release_ref" ]] || {
    echo "usage: nsc-vm-install-release <tag> [install-args...]" >&2
    exit 1
}
shift

case "$release_ref" in
    v*) ;;
    *) release_ref="v${release_ref}" ;;
esac

guest_ip="${SERVER_IP:-}"
if [[ -z "$guest_ip" ]]; then
    guest_ip="$(nsc-vm-guest-ip)"
fi
allow_insecure_sha256="${ALLOW_INSECURE_SHA256:-true}"
custom_domains="${XRAY_CUSTOM_DOMAINS:-vk.com,yoomoney.ru,cdek.ru}"
start_port="${START_PORT:-24440}"

curl -fL "https://raw.githubusercontent.com/neket371/network-stealth-core/${release_ref}/xray-reality.sh" -o /tmp/xray-reality.sh

if [[ "$(id -u)" -eq 0 ]]; then
    exec env SERVER_IP="$guest_ip" XRAY_REPO_REF="$release_ref" XRAY_CUSTOM_DOMAINS="$custom_domains" START_PORT="$start_port" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash /tmp/xray-reality.sh install "$@"
fi

exec sudo env SERVER_IP="$guest_ip" XRAY_REPO_REF="$release_ref" XRAY_CUSTOM_DOMAINS="$custom_domains" START_PORT="$start_port" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash /tmp/xray-reality.sh install "$@"
EOF
    sudo chmod 0755 /usr/local/bin/nsc-vm-install-release

    sudo tee /usr/local/bin/nsc-vm-install-repo > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo_dir="${NSC_VM_REPO_DIR:-$HOME/repo}"
script_path="${repo_dir%/}/xray-reality.sh"
[[ -f "$script_path" ]] || {
    echo "repo install script not found: $script_path" >&2
    exit 1
}

guest_ip="${SERVER_IP:-}"
if [[ -z "$guest_ip" ]]; then
    guest_ip="$(nsc-vm-guest-ip)"
fi
allow_insecure_sha256="${ALLOW_INSECURE_SHA256:-true}"

if [[ "$(id -u)" -eq 0 ]]; then
    exec env SERVER_IP="$guest_ip" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash "$script_path" install "$@"
fi

exec sudo env SERVER_IP="$guest_ip" ALLOW_INSECURE_SHA256="$allow_insecure_sha256" bash "$script_path" install "$@"
EOF
    sudo chmod 0755 /usr/local/bin/nsc-vm-install-repo

    sudo tee /etc/profile.d/90-nsc-vm-lab.sh > /dev/null << 'EOF'
#!/usr/bin/env bash

case "$-" in
    *i*) ;;
    *) return 0 ;;
esac

if [[ -n "${NSC_VM_LAB_BANNER_SHOWN:-}" ]]; then
    return 0
fi
export NSC_VM_LAB_BANNER_SHOWN=1

cat << 'MSG'
vm-lab:
  используй nsc-vm-install-latest [--num-configs n|--advanced]
  или nsc-vm-install-release <tag> [--num-configs n|--advanced]
  или nsc-vm-install-repo [--num-configs n|--advanced]
  raw curl install внутри гостя может автоопределить public ip хоста
  и завалить финальный self-check.
  release/bootstrap validation path в этом госте = nsc-vm-install-release.
  vm-lab helper'ы по умолчанию разрешают sha256 fallback,
  если у upstream xray релиза нет minisign-подписи.
MSG
EOF
    sudo chmod 0644 /etc/profile.d/90-nsc-vm-lab.sh
}

main() {
    install_guest_dependencies
    wait_for_systemd_settle

    local guest_ip
    guest_ip="$(guest_primary_ipv4)"
    [[ -n "$guest_ip" ]] || {
        echo "failed to detect guest ipv4" >&2
        exit 1
    }

    install_guest_manual_helpers

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
        E2E_PROOF_DIR="${HOME}/vm-proof"
        XRAY_CUSTOM_DOMAINS="$(vm_lab_default_custom_domains)"
    )

    if [[ -n "${INSTALL_VERSION:-}" ]]; then
        env_args+=(INSTALL_VERSION="${INSTALL_VERSION}")
    fi
    if [[ -n "${UPDATE_VERSION:-}" ]]; then
        env_args+=(UPDATE_VERSION="${UPDATE_VERSION}")
    fi

    sudo env "${env_args[@]}" bash "${ROOT_DIR}/tests/e2e/nightly_smoke_install_add_update_uninstall.sh"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
