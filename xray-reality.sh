#!/usr/bin/env bash
# Network Stealth Core 4.2.1 - Wrapper

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2> /dev/null && pwd 2> /dev/null || echo "")"
MODULE_DIR=""
DEFAULT_DATA_DIR="/usr/local/share/xray-reality"
XRAY_DATA_DIR="${XRAY_DATA_DIR:-$DEFAULT_DATA_DIR}"
REPO_URL="${XRAY_REPO_URL:-https://github.com/neket371/network-stealth-core.git}"
REPO_REF="${XRAY_REPO_REF:-${XRAY_REPO_BRANCH:-}}"
REPO_COMMIT="${XRAY_REPO_COMMIT:-}"
BOOTSTRAP_REQUIRE_PIN="${XRAY_BOOTSTRAP_REQUIRE_PIN:-true}"
BOOTSTRAP_AUTO_PIN="${XRAY_BOOTSTRAP_AUTO_PIN:-true}"
CANONICAL_BOOTSTRAP_BRANCH="ubuntu"
LEGACY_BOOTSTRAP_BRANCH="main"
BOOTSTRAP_DEFAULT_REF="${XRAY_BOOTSTRAP_DEFAULT_REF:-$CANONICAL_BOOTSTRAP_BRANCH}"
INSTALL_DIR=""
INSTALL_DIR_OWNED=false
FORWARD_ARGS=()
REQUIRED_MODULES=(
    install.sh
    config.sh
    service.sh
    health.sh
    modules/lib/validation.sh
    modules/lib/globals_contract.sh
    modules/lib/firewall.sh
    modules/lib/lifecycle.sh
    modules/lib/common_utils.sh
    modules/lib/runtime_reuse.sh
    modules/lib/domain_sources.sh
    modules/config/domain_planner.sh
    modules/config/shared_helpers.sh
    modules/config/add_clients.sh
    modules/install/bootstrap.sh
)

parse_bootstrap_bool() {
    local value="${1:-}"
    local default="${2:-false}"
    case "${value,,}" in
        1 | true | yes | y | on)
            echo "true"
            ;;
        0 | false | no | n | off)
            echo "false"
            ;;
        *)
            echo "$default"
            ;;
    esac
}

parse_wrapper_args() {
    local args=("$@")
    local i=0

    while [[ $i -lt ${#args[@]} ]]; do
        local a="${args[$i]}"
        case "$a" in
            --ref)
                i=$((i + 1))
                if [[ $i -ge ${#args[@]} ]]; then
                    echo "ERROR: --ref requires a value" >&2
                    exit 1
                fi
                REPO_REF="${args[$i]}"
                ;;
            --ref=*)
                REPO_REF="${a#*=}"
                ;;
            *)
                FORWARD_ARGS+=("$a")
                ;;
        esac
        i=$((i + 1))
    done
}

normalize_bootstrap_default_ref() {
    local value="${1:-$CANONICAL_BOOTSTRAP_BRANCH}"
    case "${value,,}" in
        "$CANONICAL_BOOTSTRAP_BRANCH")
            echo "$CANONICAL_BOOTSTRAP_BRANCH"
            ;;
        "$LEGACY_BOOTSTRAP_BRANCH")
            echo "WARN: XRAY_BOOTSTRAP_DEFAULT_REF=main is deprecated; use '$CANONICAL_BOOTSTRAP_BRANCH'" >&2
            echo "$CANONICAL_BOOTSTRAP_BRANCH"
            ;;
        release | latest-release | latest_release | release-tag | release_tag | tag)
            echo "release"
            ;;
        *)
            echo "ERROR: XRAY_BOOTSTRAP_DEFAULT_REF must be one of: $CANONICAL_BOOTSTRAP_BRANCH, release (legacy: main)" >&2
            exit 1
            ;;
    esac
}

normalize_repo_ref_alias() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 0
    case "${value,,}" in
        "$LEGACY_BOOTSTRAP_BRANCH")
            echo "WARN: XRAY_REPO_REF=main is deprecated; using '$CANONICAL_BOOTSTRAP_BRANCH'" >&2
            echo "$CANONICAL_BOOTSTRAP_BRANCH"
            ;;
        "$CANONICAL_BOOTSTRAP_BRANCH")
            echo "$CANONICAL_BOOTSTRAP_BRANCH"
            ;;
        *)
            echo "$value"
            ;;
    esac
}

has_forwarded_arg() {
    local expected="$1"
    local arg
    if ((${#FORWARD_ARGS[@]} == 0)); then
        return 1
    fi
    for arg in "${FORWARD_ARGS[@]}"; do
        if [[ "$arg" == "$expected" ]]; then
            return 0
        fi
    done
    return 1
}

require_safe_repo_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ]]; then
        echo "ERROR: unsupported repo URL (expected https://github.com/<owner>/<repo>.git): $url" >&2
        exit 1
    fi
}

prepare_install_dir() {
    INSTALL_DIR=$(mktemp -d "/tmp/xray-reality-install.XXXXXX") || {
        echo "ERROR: could not create temporary install directory" >&2
        exit 1
    }
    INSTALL_DIR_OWNED=true
}

cleanup_install_dir() {
    if [[ "$INSTALL_DIR_OWNED" == "true" && -n "${INSTALL_DIR:-}" && -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
    fi
}

module_dir_has_required_files() {
    local module_dir="$1"
    local rel
    for rel in "${REQUIRED_MODULES[@]}"; do
        if [[ ! -f "$module_dir/$rel" ]]; then
            return 1
        fi
    done
    return 0
}

resolve_module_dir() {
    local -a candidates=()
    local candidate

    [[ -n "$SCRIPT_DIR" ]] && candidates+=("$SCRIPT_DIR")
    if [[ -n "$XRAY_DATA_DIR" && "$XRAY_DATA_DIR" != "$SCRIPT_DIR" ]]; then
        candidates+=("$XRAY_DATA_DIR")
    fi

    for candidate in "${candidates[@]}"; do
        [[ -d "$candidate" ]] || continue
        if module_dir_has_required_files "$candidate"; then
            MODULE_DIR="$candidate"
            return 0
        fi
    done
    return 1
}

verify_pinned_commit() {
    local repo_dir="$1"
    local expected_commit="$2"
    local expected_lc head

    if [[ ! "$expected_commit" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        echo "ERROR: XRAY_REPO_COMMIT must be 7..40 hex chars" >&2
        exit 1
    fi

    if ! git -C "$repo_dir" fetch --quiet --depth=1 origin "$expected_commit"; then
        echo "ERROR: unable to fetch pinned commit: $expected_commit" >&2
        exit 1
    fi
    if ! git -C "$repo_dir" checkout --quiet --detach FETCH_HEAD; then
        echo "ERROR: unable to checkout pinned commit: $expected_commit" >&2
        exit 1
    fi

    head=$(git -C "$repo_dir" rev-parse HEAD)
    expected_lc="${expected_commit,,}"
    if [[ ${#expected_lc} -eq 40 ]]; then
        if [[ "$head" != "$expected_lc" ]]; then
            echo "ERROR: pinned commit mismatch (got $head, expected $expected_lc)" >&2
            exit 1
        fi
    else
        if [[ "$head" != "$expected_lc"* ]]; then
            echo "ERROR: pinned commit mismatch (got $head, expected prefix $expected_lc)" >&2
            exit 1
        fi
    fi
    echo "Pinned source commit verified: $head"
}

BOOTSTRAP_REQUIRE_PIN=$(parse_bootstrap_bool "$BOOTSTRAP_REQUIRE_PIN" true)
BOOTSTRAP_AUTO_PIN=$(parse_bootstrap_bool "$BOOTSTRAP_AUTO_PIN" true)
trap cleanup_install_dir EXIT

resolve_ref_exact_commit() {
    local repo_url="$1"
    local query="$2"
    local resolved
    resolved=$(git ls-remote --quiet "$repo_url" "$query" 2> /dev/null |
        awk -v q="$query" '$2 == q {print $1; exit}')
    if [[ "$resolved" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "${resolved,,}"
        return 0
    fi
    return 1
}

resolve_ref_commit() {
    local repo_url="$1"
    local ref="$2"
    [[ -n "$ref" ]] || return 1
    if [[ "$ref" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        echo "${ref,,}"
        return 0
    fi

    local -a candidates=()
    if [[ "$ref" == refs/* ]]; then
        candidates=("$ref")
        if [[ "$ref" == refs/tags/* ]]; then
            candidates=("${ref}^{}" "$ref")
        fi
    else
        candidates=(
            "refs/heads/$ref"
            "refs/tags/$ref^{}"
            "refs/tags/$ref"
        )
    fi

    local candidate resolved
    for candidate in "${candidates[@]}"; do
        if resolved=$(resolve_ref_exact_commit "$repo_url" "$candidate"); then
            echo "$resolved"
            return 0
        fi
    done

    if [[ "$ref" == refs/* ]]; then
        return 1
    fi
    if resolved=$(resolve_ref_exact_commit "$repo_url" "$ref"); then
        echo "$resolved"
        return 0
    fi
    return 1
}

resolve_latest_release_tag() {
    local repo_url="$1"
    local tags
    tags=$(git ls-remote --quiet --refs --tags "$repo_url" "refs/tags/v*" 2> /dev/null |
        awk '{print $2}' |
        sed 's#^refs/tags/##' |
        grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
    [[ -n "$tags" ]] || return 1

    if command -v sort > /dev/null 2>&1 && printf '1\n2\n' | sort -V > /dev/null 2>&1; then
        printf '%s\n' "$tags" | sort -V | tail -n 1
    else
        printf '%s\n' "$tags" |
            awk -F'[v.]' '{printf "%010d %010d %010d %s\n", $2, $3, $4, $0}' |
            sort |
            tail -n 1 |
            awk '{print $4}'
    fi
}

is_commit_ref() {
    local ref="${1:-}"
    [[ "$ref" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

parse_wrapper_args "$@"
BOOTSTRAP_DEFAULT_REF=$(normalize_bootstrap_default_ref "$BOOTSTRAP_DEFAULT_REF")
REPO_REF=$(normalize_repo_ref_alias "$REPO_REF")

LIB_PATH=""
for dir in "$SCRIPT_DIR" "$XRAY_DATA_DIR"; do
    if [[ -n "$dir" && -f "$dir/lib.sh" ]]; then
        LIB_PATH="$dir/lib.sh"
        break
    fi
done

if [[ -z "$LIB_PATH" ]] || { [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/config.sh" ]] && has_forwarded_arg "install"; }; then
    echo "Downloading Network Stealth Core..."
    require_safe_repo_url "$REPO_URL"
    if ! command -v git > /dev/null 2>&1; then
        if command -v apt-get > /dev/null 2>&1; then
            if ! apt-get update -qq > /dev/null 2>&1; then
                echo "ERROR: git not found and apt-get update failed" >&2
                exit 1
            fi
            if ! apt-get install -y -qq git > /dev/null 2>&1; then
                echo "ERROR: git not found and could not install it via apt-get" >&2
                exit 1
            fi
        elif command -v dnf > /dev/null 2>&1; then
            dnf -y install git > /dev/null 2>&1 || {
                echo "ERROR: git not found and could not install it via dnf" >&2
                exit 1
            }
        elif command -v yum > /dev/null 2>&1; then
            yum install -y -q git > /dev/null 2>&1 || {
                echo "ERROR: git not found and could not install it via yum" >&2
                exit 1
            }
        else
            echo "ERROR: git not found and no supported package manager detected (apt-get/dnf/yum)" >&2
            exit 1
        fi
    fi

    if [[ -z "$REPO_COMMIT" ]] && is_commit_ref "$REPO_REF"; then
        REPO_COMMIT="${REPO_REF,,}"
    fi

    if [[ -z "$REPO_REF" && -z "$REPO_COMMIT" ]]; then
        if [[ "$BOOTSTRAP_DEFAULT_REF" == "release" ]]; then
            resolved_tag="$(resolve_latest_release_tag "$REPO_URL" || true)"
            if [[ -n "$resolved_tag" ]]; then
                REPO_REF="$resolved_tag"
                echo "Using latest release tag for bootstrap: $REPO_REF"
            else
                REPO_REF="$CANONICAL_BOOTSTRAP_BRANCH"
                echo "WARN: failed to resolve latest release tag; falling back to ref '$REPO_REF'" >&2
            fi
        else
            REPO_REF="$CANONICAL_BOOTSTRAP_BRANCH"
            echo "Using default bootstrap ref: $REPO_REF"
        fi
    fi

    if [[ -z "$REPO_COMMIT" && "$BOOTSTRAP_AUTO_PIN" == "true" ]]; then
        resolved_commit="$(resolve_ref_commit "$REPO_URL" "$REPO_REF" || true)"
        if [[ -n "$resolved_commit" ]]; then
            REPO_COMMIT="$resolved_commit"
            echo "Resolved bootstrap commit: $REPO_COMMIT (ref: $REPO_REF)"
        else
            echo "WARN: failed to resolve commit for ref '$REPO_REF'; falling back to ref clone" >&2
        fi
    fi

    if [[ "$BOOTSTRAP_REQUIRE_PIN" == "true" && -z "$REPO_COMMIT" ]]; then
        echo "ERROR: XRAY_BOOTSTRAP_REQUIRE_PIN=true but XRAY_REPO_COMMIT is empty" >&2
        exit 1
    fi

    prepare_install_dir
    local_branch_args=()
    if [[ -n "$REPO_REF" ]] && ! is_commit_ref "$REPO_REF"; then
        local_branch_args=(--branch "$REPO_REF")
    fi
    git clone --quiet --depth=1 "${local_branch_args[@]}" "$REPO_URL" "$INSTALL_DIR"
    if [[ -n "$REPO_COMMIT" ]]; then
        verify_pinned_commit "$INSTALL_DIR" "$REPO_COMMIT"
    else
        echo "WARN: bootstrap source is not pinned; set XRAY_REPO_COMMIT (or XRAY_BOOTSTRAP_AUTO_PIN=true) to harden install source" >&2
    fi
    SCRIPT_DIR="$INSTALL_DIR"
    LIB_PATH="$INSTALL_DIR/lib.sh"
fi

if [[ ! -f "$LIB_PATH" ]]; then
    echo "lib.sh not found" >&2
    exit 1
fi

if ! resolve_module_dir; then
    echo "ERROR: Missing critical modules in trusted directories:" >&2
    echo "  - SCRIPT_DIR: ${SCRIPT_DIR:-<empty>}" >&2
    echo "  - XRAY_DATA_DIR: ${XRAY_DATA_DIR:-<empty>}" >&2
    echo "Try re-running the install or check the repository." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$LIB_PATH"

# shellcheck source=/dev/null
source "$MODULE_DIR/install.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/config.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/service.sh"
# shellcheck source=/dev/null
source "$MODULE_DIR/health.sh"
# shellcheck source=/dev/null
if [[ -f "$MODULE_DIR/export.sh" ]]; then
    source "$MODULE_DIR/export.sh"
fi

main "${FORWARD_ARGS[@]}"
