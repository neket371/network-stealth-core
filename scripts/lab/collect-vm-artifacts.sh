#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/collect-vm-artifacts.sh [--timestamp <ts>] [--guest-ip <ip>] [--smoke-status <code>]
EOF
}

timestamp=""
guest_ip=""
smoke_status=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timestamp)
            timestamp="${2:-}"
            shift 2
            ;;
        --guest-ip)
            guest_ip="${2:-}"
            shift 2
            ;;
        --smoke-status)
            smoke_status="${2:-}"
            shift 2
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

lab_prepare_vm_dirs

latest_env="$(lab_vm_workspace_dir)/latest-vm-run.env"
if [[ -f "$latest_env" ]]; then
    # shellcheck disable=SC1090
    source "$latest_env"
    [[ -n "$timestamp" ]] || timestamp="${LAB_VM_TIMESTAMP:-}"
    [[ -n "$guest_ip" ]] || guest_ip="${LAB_VM_GUEST_IP:-}"
    [[ -n "$smoke_status" ]] || smoke_status="${LAB_VM_SMOKE_STATUS:-}"
fi

[[ -n "$timestamp" ]] || timestamp="$(lab_timestamp)"
summary_json="$(lab_vm_workspace_dir)/lab-vm-summary-${timestamp}.json"
summary_md="$(lab_vm_workspace_dir)/lab-vm-summary-${timestamp}.md"

python3 - "$timestamp" "$guest_ip" "$smoke_status" "$summary_json" "$summary_md" "$latest_env" << 'PY'
import json
import sys
from pathlib import Path

timestamp, guest_ip, smoke_status, summary_json, summary_md, env_path = sys.argv[1:7]
summary = {
    "timestamp": timestamp,
    "vm_name": None,
    "guest_ip": guest_ip or None,
    "ssh_port": None,
    "smoke_status": int(smoke_status) if smoke_status not in ("", None) else None,
}

env_file = Path(env_path)
if env_file.exists():
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "LAB_VM_NAME":
            summary["vm_name"] = value
        elif key == "LAB_VM_SSH_PORT":
            summary["ssh_port"] = value

Path(summary_json).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
Path(summary_md).write_text(
    "\n".join(
        [
            f"# vm lab summary ({timestamp})",
            "",
            f"- vm: `{summary['vm_name'] or 'unknown'}`",
            f"- guest ip: `{summary['guest_ip'] or 'unknown'}`",
            f"- ssh port: `{summary['ssh_port'] or 'unknown'}`",
            f"- smoke status: `{summary['smoke_status']}`",
            "",
            "artifacts:",
            f"- {summary_json}",
        ]
    )
    + "\n",
    encoding="utf-8",
)
PY

printf '%s\n' "$summary_json"
