#!/usr/bin/env bash
# Network Stealth Core 7.6.3 - Wrapper

set -euo pipefail

SCRIPT_DIR="$(
    if cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2> /dev/null; then
        pwd 2> /dev/null || true
    fi
)"
if [[ -z "$SCRIPT_DIR" ]]; then
    echo "WARN: could not determine SCRIPT_DIR; local source tree is unavailable, bootstrap clone may be used." >&2
fi
MODULE_DIR=""
DEFAULT_DATA_DIR="/usr/local/share/xray-reality"
XRAY_DATA_DIR="${XRAY_DATA_DIR:-$DEFAULT_DATA_DIR}"
XRAY_ALLOW_CUSTOM_DATA_DIR="${XRAY_ALLOW_CUSTOM_DATA_DIR:-false}"
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
AUTO_PIN_RESOLVE_FAILED=false
FORWARD_ARGS=()
# keep this list compatible with historical tags used by migrate-stealth coverage.
# newer module splits must not make older pinned trees look invalid to the wrapper.
REQUIRED_BOOTSTRAP_TREE_FILES=(
    install.sh
    config.sh
    service.sh
    health.sh
    export.sh
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

normalize_wrapper_path() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 1
    if command -v realpath > /dev/null 2>&1; then
        realpath -m -- "$path" 2> /dev/null && return 0
    fi
    if command -v readlink > /dev/null 2>&1; then
        readlink -f -- "$path" 2> /dev/null && return 0
    fi
    if [[ "$path" == "/" ]]; then
        printf '/\n'
    else
        printf '%s\n' "${path%/}"
    fi
}

resolve_existing_wrapper_path() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 1
    [[ -e "$path" || -L "$path" ]] || return 1
    if command -v realpath > /dev/null 2>&1; then
        realpath -- "$path" 2> /dev/null && return 0
    fi
    if command -v readlink > /dev/null 2>&1; then
        readlink -f -- "$path" 2> /dev/null && return 0
    fi
    normalize_wrapper_path "$path"
}

is_trusted_wrapper_source_dir() {
    local candidate="${1:-}"
    local candidate_norm=""
    local script_norm=""
    local default_norm=""

    candidate_norm=$(normalize_wrapper_path "$candidate" || true)
    script_norm=$(normalize_wrapper_path "${SCRIPT_DIR:-}" || true)
    default_norm=$(normalize_wrapper_path "$DEFAULT_DATA_DIR" || true)

    [[ -n "$candidate_norm" ]] || return 1
    [[ -n "$default_norm" && "$candidate_norm" == "$default_norm" ]] && return 0
    [[ -n "$script_norm" && "$candidate_norm" == "$script_norm" ]] && return 0
    return 1
}

validate_wrapper_source_entry_trust() {
    local base_dir="${1:-}"
    local entry_path="${2:-}"
    local resolved_entry=""
    local current_dir=""
    local parent_dir=""

    resolved_entry=$(resolve_existing_wrapper_path "$entry_path" || true)
    if [[ -z "$resolved_entry" ]]; then
        echo "ERROR: wrapper could not resolve sourced file path: ${entry_path}" >&2
        exit 1
    fi

    if [[ "$resolved_entry" != "$base_dir" && "$resolved_entry" != "$base_dir"/* ]]; then
        echo "ERROR: wrapper sourced file escapes trusted XRAY_DATA_DIR tree: ${entry_path} -> ${resolved_entry}" >&2
        exit 1
    fi

    if ! has_safe_wrapper_source_permissions "$resolved_entry"; then
        echo "ERROR: wrapper sourced file has unsafe permissions: ${resolved_entry}" >&2
        exit 1
    fi

    current_dir="$(dirname "$resolved_entry")"
    while :; do
        if [[ "$current_dir" != "$base_dir" && "$current_dir" != "$base_dir"/* ]]; then
            echo "ERROR: wrapper sourced path escapes trusted XRAY_DATA_DIR tree: ${current_dir}" >&2
            exit 1
        fi
        if ! has_safe_wrapper_source_permissions "$current_dir"; then
            echo "ERROR: wrapper sourced path has unsafe permissions: ${current_dir}" >&2
            exit 1
        fi
        [[ "$current_dir" == "$base_dir" ]] && break
        parent_dir="$(dirname "$current_dir")"
        [[ "$parent_dir" != "$current_dir" ]] || break
        current_dir="$parent_dir"
    done
}

validate_wrapper_source_tree_trust() {
    local base_dir="${1:-}"
    local entry_path=""

    while IFS= read -r -d '' entry_path; do
        validate_wrapper_source_entry_trust "$base_dir" "$entry_path"
    done < <(
        find "$base_dir" -maxdepth 1 \( -type f -o -type l \) -name '*.sh' -print0
        if [[ -d "$base_dir/modules" ]]; then
            find "$base_dir/modules" \( -type f -o -type l \) -name '*.sh' -print0
        fi
    )
}

validate_wrapper_data_dir_trust() {
    local custom_norm=""

    if is_trusted_wrapper_source_dir "$XRAY_DATA_DIR"; then
        return 0
    fi

    if [[ "$XRAY_ALLOW_CUSTOM_DATA_DIR" != "true" ]]; then
        echo "ERROR: XRAY_DATA_DIR is untrusted for code sourcing: ${XRAY_DATA_DIR:-<empty>}" >&2
        echo "Allowed code-source paths by default: ${DEFAULT_DATA_DIR} or SCRIPT_DIR (${SCRIPT_DIR:-<empty>})" >&2
        echo "To explicitly allow custom code-source path, set XRAY_ALLOW_CUSTOM_DATA_DIR=true." >&2
        exit 1
    fi

    custom_norm=$(normalize_wrapper_path "$XRAY_DATA_DIR" || true)
    if [[ -z "$custom_norm" || ! -d "$custom_norm" ]]; then
        echo "ERROR: XRAY_DATA_DIR is not a valid directory: ${XRAY_DATA_DIR:-<empty>}" >&2
        exit 1
    fi

    if ! has_safe_wrapper_source_permissions "$custom_norm"; then
        echo "ERROR: XRAY_DATA_DIR has unsafe permissions (group/other writable): ${custom_norm}" >&2
        echo "Set secure permissions (for example chmod 755) before using XRAY_ALLOW_CUSTOM_DATA_DIR=true." >&2
        exit 1
    fi

    validate_wrapper_source_tree_trust "$custom_norm"
}

has_safe_wrapper_source_permissions() {
    local path="${1:-}"
    local mode=""
    local group_digit
    local other_digit

    [[ -n "$path" ]] || return 1
    [[ -e "$path" || -L "$path" ]] || return 1

    if command -v stat > /dev/null 2>&1; then
        mode=$(stat -c '%a' -- "$path" 2> /dev/null || true)
        if [[ -z "$mode" ]]; then
            mode=$(stat -f '%Lp' -- "$path" 2> /dev/null || true)
        fi
    fi

    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    mode="${mode: -3}"
    group_digit="${mode:1:1}"
    other_digit="${mode:2:1}"

    (((8#${group_digit} & 2) == 0)) || return 1
    (((8#${other_digit} & 2) == 0)) || return 1
    return 0
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

wrapper_requested_action() {
    local arg
    for arg in "${FORWARD_ARGS[@]}"; do
        case "$arg" in
            install | add-clients | add-keys | update | repair | migrate-stealth | rollback | uninstall | status | logs | diagnose | check-update)
                printf '%s\n' "$arg"
                return 0
                ;;
            --)
                break
                ;;
            *) ;;
        esac
    done
    return 1
}

wrapper_is_mutating_action() {
    case "${1:-}" in
        install | add-clients | add-keys | update | repair | migrate-stealth | rollback | uninstall)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_bootstrap_pin_warning() {
    local action="${1:-}"
    if wrapper_is_mutating_action "$action"; then
        echo "WARN: bootstrap source is not pinned for mutating action '$action'; prefer XRAY_REPO_COMMIT=<full_commit_sha> on real servers" >&2
        return 0
    fi
    echo "WARN: bootstrap source is not pinned; set XRAY_REPO_COMMIT (or XRAY_BOOTSTRAP_AUTO_PIN=true) to harden install source" >&2
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
    for rel in "${REQUIRED_BOOTSTRAP_TREE_FILES[@]}"; do
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
XRAY_ALLOW_CUSTOM_DATA_DIR=$(parse_bootstrap_bool "$XRAY_ALLOW_CUSTOM_DATA_DIR" false)
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

git_repo_head_commit() {
    local repo_dir="${1:-}"
    [[ -n "$repo_dir" ]] || return 1
    git -C "$repo_dir" rev-parse HEAD 2> /dev/null | tr '[:upper:]' '[:lower:]'
}

git_repo_ref_hint() {
    local repo_dir="${1:-}"
    local ref=""
    [[ -n "$repo_dir" ]] || return 1

    ref=$(git -C "$repo_dir" describe --tags --exact-match 2> /dev/null || true)
    [[ -n "$ref" ]] || ref=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2> /dev/null || true)
    [[ -n "$ref" ]] || ref=$(git -C "$repo_dir" rev-parse --short HEAD 2> /dev/null || true)
    [[ -n "$ref" ]] || return 1
    printf '%s\n' "$ref"
}

export_wrapper_source_metadata() {
    local kind="${1:-}"
    local repo_dir="${2:-}"
    local ref_hint="${3:-}"
    local commit_hint="${4:-}"
    local resolved_ref=""
    local resolved_commit=""

    [[ -n "$kind" ]] || return 0

    if [[ -n "$repo_dir" && -d "$repo_dir" ]]; then
        resolved_commit=$(git_repo_head_commit "$repo_dir" || true)
        resolved_ref=$(git_repo_ref_hint "$repo_dir" || true)
    fi

    [[ -n "$commit_hint" ]] && resolved_commit="$commit_hint"
    [[ -n "$ref_hint" ]] && resolved_ref="$ref_hint"

    export XRAY_SOURCE_KIND="$kind"
    if [[ -n "$resolved_ref" ]]; then
        export XRAY_SOURCE_REF="$resolved_ref"
    fi
    if [[ -n "$resolved_commit" ]]; then
        export XRAY_SOURCE_COMMIT="$resolved_commit"
    fi
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
validate_wrapper_data_dir_trust

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
            AUTO_PIN_RESOLVE_FAILED=true
            echo "WARN: failed to resolve commit for ref '$REPO_REF'; falling back to ref clone" >&2
        fi
    fi

    if [[ "$BOOTSTRAP_REQUIRE_PIN" == "true" && -z "$REPO_COMMIT" ]]; then
        if [[ "$AUTO_PIN_RESOLVE_FAILED" == "true" ]]; then
            echo "ERROR: could not pin bootstrap source for ref '$REPO_REF'." >&2
            echo "  Either set XRAY_REPO_COMMIT=<full_sha> explicitly," >&2
            echo "  or check network access to github.com (git ls-remote failed)." >&2
        else
            echo "ERROR: XRAY_BOOTSTRAP_REQUIRE_PIN=true but XRAY_REPO_COMMIT is empty" >&2
        fi
        exit 1
    fi

    prepare_install_dir
    declare -a local_branch_args=()
    if [[ -n "$REPO_REF" ]] && ! is_commit_ref "$REPO_REF"; then
        local_branch_args=(--branch "$REPO_REF")
    fi
    git clone --quiet --depth=1 "${local_branch_args[@]}" "$REPO_URL" "$INSTALL_DIR"
    if [[ -n "$REPO_COMMIT" ]]; then
        verify_pinned_commit "$INSTALL_DIR" "$REPO_COMMIT"
    else
        requested_action="$(wrapper_requested_action || true)"
        print_bootstrap_pin_warning "$requested_action"
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
source "$MODULE_DIR/export.sh"

if [[ "$INSTALL_DIR_OWNED" == "true" ]]; then
    export_wrapper_source_metadata "bootstrap" "$SCRIPT_DIR" "$REPO_REF" "$REPO_COMMIT"
elif git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    export_wrapper_source_metadata "repo-local" "$SCRIPT_DIR" "" ""
fi

main "${FORWARD_ARGS[@]}"
