#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

WORK_ROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

export TMPDIR="$WORK_ROOT/tmp"
mkdir -p "$TMPDIR" "$WORK_ROOT/bin"

source ./lib.sh
trap - EXIT
trap cleanup EXIT
source ./install.sh

XRAY_VERSION="1.2.3"
XRAY_BIN="$WORK_ROOT/bin/xray"
MINISIGN_KEY="$WORK_ROOT/minisign.pub"
SKIP_MINISIGN=true
ALLOW_INSECURE_SHA256=false
XRAY_MIRRORS="https://example.test/releases/download/v{version}"
MINISIGN_MIRRORS=""
DOWNLOAD_HOST_ALLOWLIST="example.test,github.com,ghproxy.com"

cat > "$XRAY_BIN" << 'EOF'
echo "old-binary"
EOF
chmod +x "$XRAY_BIN"
old_sha="$(sha256sum "$XRAY_BIN" | awk '{print $1}')"

download_file_allowlist() {
    return 1
}

set +e
install_xray > "$WORK_ROOT/install.log" 2>&1
rc=$?
set -e

if ((rc == 0)); then
    echo "Expected install_xray to fail when all mirrors are unavailable" >&2
    cat "$WORK_ROOT/install.log" >&2 || true
    exit 1
fi

if ! grep -q "Не удалось получить официальный .dgst для Xray release" "$WORK_ROOT/install.log"; then
    echo "Expected official digest failure message in install log" >&2
    cat "$WORK_ROOT/install.log" >&2 || true
    exit 1
fi

new_sha="$(sha256sum "$XRAY_BIN" | awk '{print $1}')"
if [[ "$old_sha" != "$new_sha" ]]; then
    echo "Existing binary was unexpectedly changed after failed download" >&2
    exit 1
fi

if find "$TMPDIR" -maxdepth 1 -type d \( -name "xray-${XRAY_VERSION}.*" -o -name "xray-install.*" \) | grep -q .; then
    echo "Temporary install directories were not cleaned after download failure" >&2
    find "$TMPDIR" -maxdepth 2 -print >&2 || true
    exit 1
fi

echo "e2e download failure rollback check passed."
