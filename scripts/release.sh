#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat << 'EOF'
Usage: scripts/release.sh <version> [--commit] [--tag] [--push]

Examples:
  scripts/release.sh 4.1.6
  scripts/release.sh 4.1.6 --commit
  scripts/release.sh 4.1.6 --commit --tag --push

What it does:
  1. Updates SCRIPT_VERSION and header version in lib.sh
  2. Updates wrapper header version in xray-reality.sh
  3. Updates release badge versions and release-tag bootstrap examples in README.md and README.ru.md
  4. Updates release-facing issue template placeholders
  5. Moves current [unreleased] notes into the target changelog section and falls back to git-log notes when unreleased is empty
  6. Runs shared release consistency checks
  7. Optionally commits, tags and pushes
     (push target: current branch, or RELEASE_PUSH_BRANCH override)
EOF
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

VERSION="$1"
shift

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version: $VERSION (expected MAJOR.MINOR.PATCH)" >&2
    exit 1
fi

DO_COMMIT=false
DO_TAG=false
DO_PUSH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit)
            DO_COMMIT=true
            ;;
        --tag)
            DO_TAG=true
            ;;
        --push)
            DO_PUSH=true
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown flag: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_FILE="$ROOT_DIR/lib.sh"
WRAPPER_FILE="$ROOT_DIR/xray-reality.sh"
README_EN="$ROOT_DIR/README.md"
README_RU="$ROOT_DIR/README.ru.md"
CHANGELOG_EN="$ROOT_DIR/docs/en/CHANGELOG.md"
CHANGELOG_RU="$ROOT_DIR/docs/ru/CHANGELOG.md"
BUG_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.yml"
SUPPORT_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/support_request.yml"
TAG="v$VERSION"
TODAY="$(date +%Y-%m-%d)"
NOTES_TMP="$(mktemp)"
trap 'rm -f "$NOTES_TMP"' EXIT

cd "$ROOT_DIR"

for file in "$LIB_FILE" "$WRAPPER_FILE" "$README_EN" "$README_RU" "$CHANGELOG_EN" "$CHANGELOG_RU" "$BUG_TEMPLATE" "$SUPPORT_TEMPLATE"; do
    [[ -f "$file" ]] || {
        echo "Missing required file: $file" >&2
        exit 1
    }
done

generate_release_notes() {
    local previous_tag
    previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2> /dev/null || true)"
    local log_range=()
    if [[ -n "$previous_tag" ]]; then
        log_range=("$previous_tag..HEAD")
    fi

    local notes
    notes="$(git log --no-merges --pretty='- %s (%h)' "${log_range[@]}" 2> /dev/null || true)"
    if [[ -z "$notes" ]]; then
        notes="- maintenance release"
    fi
    printf '%s\n' "$notes"
}

validate_generated_release_notes() {
    if [[ ! -s "$NOTES_TMP" ]] || ! grep -q '[^[:space:]]' "$NOTES_TMP"; then
        echo "Generated release notes are empty; refusing release." >&2
        exit 1
    fi
}

insert_changelog_section() {
    local changelog_file="$1"
    local tmp_file
    tmp_file="$(mktemp "${changelog_file}.tmp.XXXXXX")"
    awk -v ver="$VERSION" -v day="$TODAY" -v notes_file="$NOTES_TMP" '
        function trim_pending_body( idx ) {
            for (; pending_body_count > 0 && pending_body[pending_body_count] == ""; pending_body_count--) {
                delete pending_body[pending_body_count]
            }
        }
        function print_release_section( note_line, idx ) {
            print "## [" ver "] - " day
            print ""
            trim_pending_body()
            if (pending_body_count > 0) {
                for (idx = 1; idx <= pending_body_count; idx++) {
                    print pending_body[idx]
                }
            } else {
                print "### Changed"
                for (; (getline note_line < notes_file) > 0; ) {
                    print note_line
                }
                close(notes_file)
            }
            print ""
        }
        BEGIN {
            inserted = 0
            in_unreleased = 0
            pending_body_count = 0
        }
        {
            if (!inserted && tolower($0) ~ /^## \[unreleased\]/) {
                print
                print ""
                in_unreleased = 1
                next
            }

            if (in_unreleased) {
                if ($0 ~ /^## \[/) {
                    print_release_section()
                    print
                    inserted = 1
                    in_unreleased = 0
                    next
                }
                if ($0 ~ /^[[:space:]]*$/) {
                    if (pending_body_count > 0 && pending_body[pending_body_count] != "") {
                        pending_body[++pending_body_count] = ""
                    }
                } else {
                    pending_body[++pending_body_count] = $0
                }
                next
            }
            print
        }
        END {
            if (in_unreleased) {
                print_release_section()
                inserted = 1
            }
            if (!inserted) {
                exit 2
            }
        }
    ' "$changelog_file" > "$tmp_file" || {
        rm -f "$tmp_file"
        echo "Failed to update ${changelog_file#"$ROOT_DIR"/} (missing ## [unreleased]?)" >&2
        exit 1
    }
    mv "$tmp_file" "$changelog_file"
}

replace_release_todo() {
    local changelog_file="$1"
    if ! grep -q "^- TODO: summarize release changes$" "$changelog_file"; then
        return 0
    fi
    local tmp_file
    tmp_file="$(mktemp "${changelog_file}.tmp.XXXXXX")"
    awk -v notes_file="$NOTES_TMP" '
        function emit_notes( line ) {
            for (; (getline line < notes_file) > 0; ) {
                print line
            }
            close(notes_file)
        }
        {
            if ($0 == "- TODO: summarize release changes") {
                emit_notes()
                next
            }
            print
        }
    ' "$changelog_file" > "$tmp_file"
    mv "$tmp_file" "$changelog_file"
}

ensure_release_section_has_no_todo() {
    local changelog_file="$1"
    if awk -v ver="$VERSION" '
        BEGIN { in_target = 0; found = 0 }
        $0 ~ "^## \\[" ver "\\]" { in_target = 1; next }
        $0 ~ "^## \\[" {
            if (in_target) {
                in_target = 0
            }
        }
        in_target && $0 == "- TODO: summarize release changes" {
            found = 1
        }
        END {
            exit found ? 0 : 1
        }
    ' "$changelog_file"; then
        echo "${changelog_file#"$ROOT_DIR"/} section [$VERSION] still contains TODO placeholder" >&2
        exit 1
    fi
}

replace_with_sed() {
    local expr="$1"
    local file="$2"
    local tmp_file
    tmp_file="$(mktemp "${file}.tmp.XXXXXX")"
    sed -E "$expr" "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}

generate_release_notes > "$NOTES_TMP"
validate_generated_release_notes

replace_with_sed 's/^readonly SCRIPT_VERSION="[^"]+"/readonly SCRIPT_VERSION="'"$VERSION"'"/' "$LIB_FILE"
replace_with_sed 's/^# Network Stealth Core [0-9]+\.[0-9]+\.[0-9]+ - /# Network Stealth Core '"$VERSION"' - /' "$LIB_FILE"
replace_with_sed 's/^# Network Stealth Core [0-9]+\.[0-9]+\.[0-9]+ - Wrapper/# Network Stealth Core '"$VERSION"' - Wrapper/' "$WRAPPER_FILE"
replace_with_sed 's/release-v[0-9]+\.[0-9]+\.[0-9]+/release-v'"$VERSION"'/g' "$README_EN"
replace_with_sed 's/release-v[0-9]+\.[0-9]+\.[0-9]+/release-v'"$VERSION"'/g' "$README_RU"
replace_with_sed 's#raw.githubusercontent.com/neket371/network-stealth-core/v[0-9]+\.[0-9]+\.[0-9]+/xray-reality\.sh#raw.githubusercontent.com/neket371/network-stealth-core/v'"$VERSION"'/xray-reality.sh#g' "$README_EN"
replace_with_sed 's#raw.githubusercontent.com/neket371/network-stealth-core/v[0-9]+\.[0-9]+\.[0-9]+/xray-reality\.sh#raw.githubusercontent.com/neket371/network-stealth-core/v'"$VERSION"'/xray-reality.sh#g' "$README_RU"
replace_with_sed 's/XRAY_REPO_REF=v[0-9]+\.[0-9]+\.[0-9]+/XRAY_REPO_REF=v'"$VERSION"'/g' "$README_EN"
replace_with_sed 's/XRAY_REPO_REF=v[0-9]+\.[0-9]+\.[0-9]+/XRAY_REPO_REF=v'"$VERSION"'/g' "$README_RU"
replace_with_sed 's#placeholder: v[0-9]+\.[0-9]+\.[0-9]+ / .*#placeholder: v'"$VERSION"' / <full_commit_sha> / ubuntu@<sha>#' "$BUG_TEMPLATE"
replace_with_sed 's#placeholder: v[0-9]+\.[0-9]+\.[0-9]+ / .*#placeholder: v'"$VERSION"' / <full_commit_sha> / ubuntu@<sha>#' "$SUPPORT_TEMPLATE"

for changelog_file in "$CHANGELOG_EN" "$CHANGELOG_RU"; do
    if ! grep -q "^## \[$VERSION\]" "$changelog_file"; then
        insert_changelog_section "$changelog_file"
    fi
    replace_release_todo "$changelog_file"
    ensure_release_section_has_no_todo "$changelog_file"
done

bash "$ROOT_DIR/scripts/check-release-consistency.sh"

echo "Updated files for $TAG:"
echo "  - lib.sh"
echo "  - xray-reality.sh"
echo "  - README.md"
echo "  - README.ru.md"
echo "  - docs/en/CHANGELOG.md"
echo "  - docs/ru/CHANGELOG.md"
echo "  - .github/ISSUE_TEMPLATE/bug_report.yml"
echo "  - .github/ISSUE_TEMPLATE/support_request.yml"

if [[ "$DO_COMMIT" == true ]]; then
    git add lib.sh xray-reality.sh README.md README.ru.md docs/en/CHANGELOG.md docs/ru/CHANGELOG.md \
        .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/support_request.yml
    if git diff --cached --quiet; then
        echo "No staged changes to commit."
    else
        git commit -m "release: prepare $TAG"
        echo "Committed: release: prepare $TAG"
    fi
fi

if [[ "$DO_TAG" == true ]]; then
    if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
        echo "Tag already exists: $TAG" >&2
        exit 1
    fi
    git tag -a "$TAG" -m "$TAG"
    echo "Created tag: $TAG"
fi

if [[ "$DO_PUSH" == true ]]; then
    push_branch="${RELEASE_PUSH_BRANCH:-$(git symbolic-ref --quiet --short HEAD 2> /dev/null || true)}"
    if [[ -z "$push_branch" ]]; then
        echo "Cannot determine push branch (set RELEASE_PUSH_BRANCH explicitly)." >&2
        exit 1
    fi
    if [[ "$DO_COMMIT" == true ]]; then
        git push origin "$push_branch"
    fi
    if [[ "$DO_TAG" == true ]]; then
        git push origin "$TAG"
    fi
fi

echo "Done."
