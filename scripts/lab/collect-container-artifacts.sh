#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lab/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat << 'EOF'
usage:
  bash scripts/lab/collect-container-artifacts.sh [--timestamp <ts>]
EOF
}

timestamp=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timestamp)
            timestamp="${2:-}"
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

lab_prepare_dirs
lab_resolve_runtime_access

latest_env="$(lab_workspace_dir)/latest-run.env"
if [[ -z "$timestamp" && -f "$latest_env" ]]; then
    # shellcheck disable=SC1090
    source "$latest_env"
    timestamp="${LAB_TIMESTAMP:-}"
fi
[[ -n "$timestamp" ]] || timestamp="$(lab_timestamp)"

inspect_file="$(lab_logs_dir)/container-inspect-${timestamp}.json"
summary_json="$(lab_workspace_dir)/lab-summary-${timestamp}.json"
summary_md="$(lab_workspace_dir)/lab-summary-${timestamp}.md"

lab_runtime inspect "$(lab_container_name)" > "$inspect_file" 2> /dev/null || printf '%s\n' '[]' > "$inspect_file"

python3 - "$timestamp" "$inspect_file" "$summary_json" "$summary_md" << 'PY'
import json
import sys
from pathlib import Path

timestamp, inspect_file, summary_json, summary_md = sys.argv[1:5]
inspect_path = Path(inspect_file)
inspect_data = json.loads(inspect_path.read_text(encoding="utf-8"))
container = inspect_data[0] if inspect_data else {}
state = container.get("State", {})
config = container.get("Config", {})
host_config = container.get("HostConfig", {})

summary = {
    "timestamp": timestamp,
    "container_name": container.get("Name", "").lstrip("/"),
    "status": state.get("Status"),
    "running": state.get("Running"),
    "exit_code": state.get("ExitCode"),
    "image": config.get("Image"),
    "network_mode": host_config.get("NetworkMode"),
    "published_ports": container.get("NetworkSettings", {}).get("Ports", {}),
}

Path(summary_json).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

lines = [
    f"# lab summary ({timestamp})",
    "",
    f"- container: `{summary['container_name'] or 'unknown'}`",
    f"- status: `{summary['status']}`",
    f"- running: `{summary['running']}`",
    f"- exit code: `{summary['exit_code']}`",
    f"- image: `{summary['image']}`",
    f"- network mode: `{summary['network_mode']}`",
    f"- published ports: `{summary['published_ports']}`",
    "",
    "artifacts:",
    f"- {summary_json}",
    f"- {inspect_file}",
]
Path(summary_md).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

printf '%s\n' "$summary_json"
