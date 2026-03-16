#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << 'EOF'
Usage: scripts/check-release-consistency.sh [--tag vMAJOR.MINOR.PATCH]

Checks release metadata consistency across:
  - lib.sh SCRIPT_VERSION
  - lib.sh header version
  - xray-reality.sh wrapper header version
  - README.md / README.ru.md release badges
  - README.md / README.ru.md exact release-tag bootstrap example
  - docs/en/CHANGELOG.md version section
  - docs/ru/CHANGELOG.md version section
  - issue template placeholders for version/commit reporting

Optional:
  --tag TAG   additionally requires TAG == vSCRIPT_VERSION
EOF
}

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            TAG="${2:-}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -n "$TAG" && ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Tag must match vMAJOR.MINOR.PATCH, got: $TAG" >&2
    exit 1
fi

LIB_FILE="$ROOT_DIR/lib.sh"
WRAPPER_FILE="$ROOT_DIR/xray-reality.sh"
README_EN="$ROOT_DIR/README.md"
README_RU="$ROOT_DIR/README.ru.md"
CHANGELOG_FILE="$ROOT_DIR/docs/en/CHANGELOG.md"
CHANGELOG_FILE_RU="$ROOT_DIR/docs/ru/CHANGELOG.md"
BUG_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.yml"
SUPPORT_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/support_request.yml"

for file in "$LIB_FILE" "$WRAPPER_FILE" "$README_EN" "$README_RU" "$CHANGELOG_FILE" "$CHANGELOG_FILE_RU" "$BUG_TEMPLATE" "$SUPPORT_TEMPLATE"; do
    [[ -f "$file" ]] || {
        echo "Missing required file: $file" >&2
        exit 1
    }
done

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if ! grep -q "$pattern" "$file"; then
        echo "Missing or mismatched ${label} in ${file#"$ROOT_DIR"/}" >&2
        exit 1
    fi
}

script_version=$(awk -F'"' '/^readonly SCRIPT_VERSION=/{print $2; exit}' "$LIB_FILE")
if [[ -z "$script_version" ]]; then
    echo "Failed to detect SCRIPT_VERSION from lib.sh" >&2
    exit 1
fi
if [[ ! "$script_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "SCRIPT_VERSION must match MAJOR.MINOR.PATCH, got: $script_version" >&2
    exit 1
fi

require_pattern "$LIB_FILE" "^# Network Stealth Core ${script_version} - " "lib.sh header version"
require_pattern "$WRAPPER_FILE" "^# Network Stealth Core ${script_version} - Wrapper" "wrapper header version"
require_pattern "$README_EN" "release-v${script_version}" "README.md release badge version"
require_pattern "$README_RU" "release-v${script_version}" "README.ru.md release badge version"
require_pattern "$README_EN" "raw.githubusercontent.com/neket371/network-stealth-core/v${script_version}/xray-reality.sh" "README.md release-tag bootstrap url"
require_pattern "$README_RU" "raw.githubusercontent.com/neket371/network-stealth-core/v${script_version}/xray-reality.sh" "README.ru.md release-tag bootstrap url"
require_pattern "$README_EN" "XRAY_REPO_REF=v${script_version}" "README.md release-tag bootstrap ref"
require_pattern "$README_RU" "XRAY_REPO_REF=v${script_version}" "README.ru.md release-tag bootstrap ref"
require_pattern "$CHANGELOG_FILE" "^## \\[${script_version}\\]" "docs/en/CHANGELOG.md section"
require_pattern "$CHANGELOG_FILE_RU" "^## \\[${script_version}\\]" "docs/ru/CHANGELOG.md section"
require_pattern "$BUG_TEMPLATE" "^      placeholder: v${script_version} / <full_commit_sha> / ubuntu@<sha>$" "bug template placeholder"
require_pattern "$SUPPORT_TEMPLATE" "^      placeholder: v${script_version} / <full_commit_sha> / ubuntu@<sha>$" "support template placeholder"

if awk '
    BEGIN { in_released = 0; bad = 0 }
    $0 ~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { in_released = 1; next }
    $0 ~ /^## \[/ {
        in_released = 0
        next
    }
    in_released && $0 == "- TODO: summarize release changes" {
        bad = 1
    }
    END {
        exit bad ? 0 : 1
    }
' "$CHANGELOG_FILE"; then
    echo "CHANGELOG contains TODO placeholder inside a released section" >&2
    exit 1
fi

if ! awk -v ver="$script_version" '
    BEGIN { in_target = 0; has_bullet = 0 }
    $0 ~ "^## \\[" ver "\\]" { in_target = 1; next }
    $0 ~ /^## \[/ {
        if (in_target) {
            in_target = 0
        }
        next
    }
    in_target && $0 ~ /^- / {
        has_bullet = 1
    }
    END {
        exit has_bullet ? 0 : 1
    }
' "$CHANGELOG_FILE"; then
    echo "CHANGELOG section [${script_version}] does not contain release bullet notes" >&2
    exit 1
fi

if ! awk -v ver="$script_version" '
    BEGIN { in_target = 0; has_bullet = 0 }
    $0 ~ "^## \\[" ver "\\]" { in_target = 1; next }
    $0 ~ /^## \[/ {
        if (in_target) {
            in_target = 0
        }
        next
    }
    in_target && $0 ~ /^- / {
        has_bullet = 1
    }
    END {
        exit has_bullet ? 0 : 1
    }
' "$CHANGELOG_FILE_RU"; then
    echo "RU CHANGELOG section [${script_version}] does not contain release bullet notes" >&2
    exit 1
fi

if [[ -n "$TAG" && "v${script_version}" != "$TAG" ]]; then
    echo "Tag ${TAG} does not match SCRIPT_VERSION v${script_version}" >&2
    exit 1
fi

echo "release-consistency-ok:${script_version}"
if [[ -n "$TAG" ]]; then
    echo "tag-match-ok:${TAG}"
fi
