#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob

if ! command -v rg > /dev/null 2>&1; then
    echo "dead-function-check: rg (ripgrep) is required in PATH" >&2
    exit 2
fi

FILES=(
    "$ROOT_DIR/xray-reality.sh"
    "$ROOT_DIR/lib.sh"
    "$ROOT_DIR/install.sh"
    "$ROOT_DIR/config.sh"
    "$ROOT_DIR/service.sh"
    "$ROOT_DIR/health.sh"
    "$ROOT_DIR/export.sh"
    "$ROOT_DIR"/scripts/*.sh
    "$ROOT_DIR"/modules/lib/*.sh
    "$ROOT_DIR"/modules/config/*.sh
    "$ROOT_DIR"/modules/service/*.sh
    "$ROOT_DIR"/modules/install/*.sh
    "$ROOT_DIR"/modules/health/*.sh
    "$ROOT_DIR"/modules/export/*.sh
)

IGNORED_FUNCTIONS=(
    # Keep exact-name allowlist support for intentional wrappers if they appear later.
)

dead_function_is_ignored() {
    local fn="${1:-}"
    local ignored
    for ignored in "${IGNORED_FUNCTIONS[@]}"; do
        [[ "$fn" == "$ignored" ]] && return 0
    done
    return 1
}

declare -a DEFS=()
declare -a FILTERED_DEFS=()
declare -a DEAD=()
declare -a FN_NAMES=()
declare -A FN_SEEN=()

for file in "${FILES[@]}"; do
    while IFS=: read -r line fn; do
        [[ -n "$line" && -n "$fn" ]] || continue
        DEFS+=("${file}|${line}|${fn}")
        if [[ -z "${FN_SEEN[$fn]:-}" ]]; then
            FN_SEEN["$fn"]=1
            FN_NAMES+=("$fn")
        fi
    done < <(rg -n -o --pcre2 '^[A-Za-z_][A-Za-z0-9_]*(?=\(\)\s*\{)' "$file" || true)
done

for def in "${DEFS[@]}"; do
    IFS='|' read -r file line fn <<< "$def"
    if dead_function_is_ignored "$fn"; then
        continue
    fi
    FILTERED_DEFS+=("$def")
done

combined_pattern=""
if ((${#FN_NAMES[@]} > 0)); then
    combined_pattern="(^|[^A-Za-z0-9_])($(
        IFS='|'
        printf '%s' "${FN_NAMES[*]}"
    ))([^A-Za-z0-9_]|$)"
fi

defs_tmp="$(mktemp)"
matches_tmp="$(mktemp)"
trap 'rm -f "$defs_tmp" "$matches_tmp"' EXIT

printf '%s\n' "${FILTERED_DEFS[@]}" > "$defs_tmp"
if [[ -n "$combined_pattern" ]]; then
    rg -n --pcre2 "$combined_pattern" "${FILES[@]}" > "$matches_tmp" || true
fi

mapfile -t DEAD < <(awk '
        function strip_shell_literals(s,    out, i, ch, state, sq, cmd_depth) {
            out = ""
            state = "code"
            sq = sprintf("%c", 39)
            cmd_depth = 0
            for (i = 1; i <= length(s); i++) {
                ch = substr(s, i, 1)
                if (state == "code") {
                    if (ch == "#") {
                        break
                    }
                    if (ch == "\"") {
                        state = "dquote"
                        continue
                    }
                    if (ch == sq) {
                        state = "squote"
                        continue
                    }
                    out = out ch
                    continue
                }
                if (state == "dquote") {
                    if (ch == "$" && substr(s, i + 1, 1) == "(") {
                        out = out "$("
                        i++
                        cmd_depth = 1
                        state = "dquote_cmd"
                        continue
                    }
                    if (ch == "\\") {
                        i++
                        continue
                    }
                    if (ch == "\"") {
                        state = "code"
                    }
                    continue
                }
                if (state == "dquote_cmd") {
                    if (ch == "\\") {
                        out = out ch
                        i++
                        if (i <= length(s)) {
                            out = out substr(s, i, 1)
                        }
                        continue
                    }
                    if (ch == "$" && substr(s, i + 1, 1) == "(") {
                        out = out "$("
                        i++
                        cmd_depth++
                        continue
                    }
                    out = out ch
                    if (ch == ")") {
                        cmd_depth--
                        if (cmd_depth <= 0) {
                            state = "dquote"
                            cmd_depth = 0
                        }
                    }
                    continue
                }
                if (state == "squote") {
                    if (ch == "\\") {
                        i++
                        continue
                    }
                    if (ch == sq) {
                        state = "code"
                    }
                    continue
                }
            }
            return out
        }
        ARGIND == 1 {
            split($0, def_parts, "|")
            def_file = def_parts[1]
            def_line = def_parts[2]
            def_fn = def_parts[3]
            def_present[def_fn] = 1
            def_location[def_fn SUBSEP def_file SUBSEP def_line] = 1
            def_records[++def_count] = $0
            next
        }
        ARGIND == 2 {
            raw=$0
            if (match(raw, /:[0-9]+:/)) {
                match_file=substr(raw, 1, RSTART - 1)
                match_line=substr(raw, RSTART + 1, RLENGTH - 2)
                text=substr(raw, RSTART + RLENGTH)
            } else {
                next
            }

            clean=strip_shell_literals(text)
            if (clean ~ "^[[:space:]]*$") {
                next
            }
            remaining = clean
            for (; match(remaining, /[A-Za-z_][A-Za-z0-9_]*/); remaining = substr(remaining, RSTART + RLENGTH)) {
                token = substr(remaining, RSTART, RLENGTH)
                if (!(token in def_present)) {
                    continue
                }
                if ((token SUBSEP match_file SUBSEP match_line) in def_location) {
                    continue
                }
                if (clean ~ ("^[[:space:]]*" token "\\(\\)[[:space:]]*\\{")) {
                    continue
                }
                called[token] = 1
            }
        }
        END {
            for (i = 1; i <= def_count; i++) {
                split(def_records[i], def_parts, "|")
                def_file = def_parts[1]
                def_line = def_parts[2]
                def_fn = def_parts[3]
                if (!(def_fn in called)) {
                    printf "%s (%s:%s)\n", def_fn, def_file, def_line
                }
            }
        }
    ' "$defs_tmp" "$matches_tmp")

if ((${#DEAD[@]} > 0)); then
    echo "dead-function-check: found functions without call sites" >&2
    printf '  - %s\n' "${DEAD[@]}" >&2
    exit 1
fi

echo "dead-function-check: ok"
