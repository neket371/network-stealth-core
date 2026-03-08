#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/run-container-smoke.sh

environment:
  LAB_RUNTIME           docker|podman|auto (default: auto)
  LAB_HOST_ROOT         host directory for workspace/logs/artifacts
  LAB_CONTAINER_NAME    container name (default: nsc-lab-2404)
  LAB_IMAGE             container image (default: ubuntu:24.04)
  LAB_START_PORT        smoke start port (default: 25040)
  LAB_NUM_CONFIGS       config count for smoke install (default: 1)
  LAB_XRAY_VERSION      optional xray version override
  LAB_KEEP_CONTAINER    keep the container running after the smoke test (default: false)
  LAB_REMOVE_CONTAINER  remove the container after the smoke test (default: false)
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

start_port="${LAB_START_PORT:-25040}"
num_configs="${LAB_NUM_CONFIGS:-1}"
container_name="$(lab_container_name)"
container_image="$(lab_container_image)"
workspace_dir="$(lab_workspace_dir)"
logs_dir="$(lab_logs_dir)"
artifacts_dir="$(lab_artifacts_dir)"
timestamp="$(lab_timestamp)"
keep_container="${LAB_KEEP_CONTAINER:-false}"
remove_container="${LAB_REMOVE_CONTAINER:-false}"
summary_file="${workspace_dir}/latest-run.env"

cleanup_container() {
    if [[ "$keep_container" == "true" ]]; then
        return 0
    fi
    lab_runtime stop "$container_name" > /dev/null 2>&1 || true
    if [[ "$remove_container" == "true" ]]; then
        lab_runtime rm -f "$container_name" > /dev/null 2>&1 || true
    fi
}
trap cleanup_container EXIT

lab_remove_container_if_present
lab_runtime pull "$container_image" > /dev/null

lab_runtime create \
    --name "$container_name" \
    --hostname "$container_name" \
    --label owner=network-stealth-core \
    --label purpose=host-safe-lab-smoke \
    --security-opt no-new-privileges \
    --memory "${LAB_CONTAINER_MEMORY:-2g}" \
    --pids-limit "${LAB_PIDS_LIMIT:-512}" \
    -v "${LAB_ROOT_DIR}:/workspace/repo:ro" \
    -v "${workspace_dir}:/lab-workspace" \
    -v "${logs_dir}:/lab-logs" \
    -v "${artifacts_dir}:/lab-artifacts" \
    "$container_image" sleep infinity > /dev/null

lab_runtime start "$container_name" > /dev/null

install_log="/lab-logs/install-smoke-${timestamp}.log"
status_log="/lab-logs/status-${timestamp}.log"
runtime_log="/lab-logs/manual-xray-run-${timestamp}.log"
runtime_test_log="/lab-logs/manual-xray-test-${timestamp}.log"
runtime_listen_log="/lab-logs/manual-xray-listen-${timestamp}.log"

set +e
lab_runtime exec "$container_name" bash -lc "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq bash ca-certificates curl jq iproute2 logrotate openssl procps unzip uuid-runtime python3 >/dev/null
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export LC_CTYPE=C.UTF-8
export NON_INTERACTIVE=true
export ASSUME_YES=true
export ALLOW_NO_SYSTEMD=true
export ALLOW_INSECURE_SHA256=true
export SERVER_IP=127.0.0.1
export DOMAIN_CHECK=false
export SKIP_REALITY_CHECK=true
export XRAY_NUM_CONFIGS='${num_configs}'
export START_PORT='${start_port}'
export PROGRESS_MODE=plain
if [[ -n '${LAB_XRAY_VERSION:-}' ]]; then
  export XRAY_VERSION='${LAB_XRAY_VERSION:-}'
fi
bash /workspace/repo/xray-reality.sh install --non-interactive --yes 2>&1 | tee '${install_log}'
bash /workspace/repo/xray-reality.sh status --verbose 2>&1 | tee '${status_log}' > /lab-workspace/status-${timestamp}.txt
/usr/local/bin/xray run -test -config /etc/xray/config.json > '${runtime_test_log}' 2>&1
nohup /usr/local/bin/xray run -config /etc/xray/config.json > '${runtime_log}' 2>&1 &
pid=\$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ss -ltnp | grep -q ':${start_port} '; then
    break
  fi
  sleep 1
done
ss -ltnp | grep ':${start_port} ' > '${runtime_listen_log}'
kill \$pid
wait \$pid || true
cp -a /var/log/xray-install.log /lab-logs/xray-install-${timestamp}.log 2>/dev/null || true
cp -a /etc/xray/config.json /lab-artifacts/config-${timestamp}.json
cp -a /etc/xray/private/keys /lab-artifacts/keys-${timestamp}
"
smoke_status=$?
set -e

cat > "$summary_file" << EOF
LAB_TIMESTAMP=${timestamp}
LAB_CONTAINER_NAME=${container_name}
LAB_IMAGE=${container_image}
LAB_RUNTIME=${LAB_RUNTIME_BIN}
LAB_HOST_ROOT=$(lab_host_root)
LAB_START_PORT=${start_port}
LAB_NUM_CONFIGS=${num_configs}
LAB_SMOKE_STATUS=${smoke_status}
EOF

result_json="$(bash "$SCRIPT_DIR/collect-container-artifacts.sh" --timestamp "$timestamp")"

if ((smoke_status != 0)); then
    echo "lab smoke failed; inspect ${install_log}, ${status_log}, ${runtime_test_log}, ${runtime_log}" >&2
    echo "lab summary: ${result_json}" >&2
    exit "$smoke_status"
fi

cat << EOF
lab smoke: ok
host root: $(lab_host_root)
container: ${container_name}
runtime: ${LAB_RUNTIME_BIN}
logs: ${logs_dir}
artifacts: ${artifacts_dir}
summary: ${result_json}
EOF
