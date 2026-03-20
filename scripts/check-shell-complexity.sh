#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPLEXITY_STAGE="${COMPLEXITY_STAGE:-2}"
MAX_FUNC_LINES="${MAX_FUNC_LINES:-}"
MAX_FILE_LINES="${MAX_FILE_LINES:-}"
MAX_BATS_FILE_LINES="${MAX_BATS_FILE_LINES:-}"
MAX_BATS_TEST_LINES="${MAX_BATS_TEST_LINES:-}"
MAX_PS1_FILE_LINES="${MAX_PS1_FILE_LINES:-}"

if [[ -z "$MAX_FUNC_LINES" || -z "$MAX_FILE_LINES" || -z "$MAX_BATS_FILE_LINES" || -z "$MAX_BATS_TEST_LINES" || -z "$MAX_PS1_FILE_LINES" ]]; then
    case "$COMPLEXITY_STAGE" in
        1)
            MAX_FUNC_LINES=420
            MAX_FILE_LINES=3200
            MAX_BATS_FILE_LINES=6000
            MAX_BATS_TEST_LINES=320
            MAX_PS1_FILE_LINES=1400
            ;;
        2)
            MAX_FUNC_LINES=360
            MAX_FILE_LINES=3000
            MAX_BATS_FILE_LINES=5500
            MAX_BATS_TEST_LINES=280
            MAX_PS1_FILE_LINES=1200
            ;;
        3)
            MAX_FUNC_LINES=320
            MAX_FILE_LINES=2800
            MAX_BATS_FILE_LINES=5200
            MAX_BATS_TEST_LINES=260
            MAX_PS1_FILE_LINES=1000
            ;;
        4)
            MAX_FUNC_LINES=280
            MAX_FILE_LINES=2600
            MAX_BATS_FILE_LINES=4800
            MAX_BATS_TEST_LINES=220
            MAX_PS1_FILE_LINES=900
            ;;
        *)
            echo "complexity check fail: unsupported COMPLEXITY_STAGE=${COMPLEXITY_STAGE}" >&2
            exit 1
            ;;
    esac
fi

fail=0
SHELL_FILES=()
BATS_FILES=()
POWERSHELL_FILES=()

if command -v rg > /dev/null 2>&1; then
    while IFS= read -r file; do
        file="${file//\\//}"
        SHELL_FILES+=("$file")
    done < <(rg --files \
        -g '*.sh' \
        xray-reality.sh lib.sh install.sh config.sh service.sh health.sh export.sh \
        scripts modules)
    while IFS= read -r file; do
        file="${file//\\//}"
        BATS_FILES+=("$file")
    done < <(rg --files -g '*.bats' tests/bats)
    while IFS= read -r file; do
        file="${file//\\//}"
        POWERSHELL_FILES+=("$file")
    done < <(rg --files -g '*.ps1' scripts)
else
    SHELL_FILES=(
        xray-reality.sh
        lib.sh
        install.sh
        config.sh
        service.sh
        health.sh
        export.sh
    )
    while IFS= read -r file; do
        SHELL_FILES+=("${file#./}")
    done < <(find scripts modules -type f -name '*.sh' -print)
    while IFS= read -r file; do
        BATS_FILES+=("${file#./}")
    done < <(find tests/bats -type f -name '*.bats' -print)
    while IFS= read -r file; do
        POWERSHELL_FILES+=("${file#./}")
    done < <(find scripts -type f -name '*.ps1' -print)
fi

if ((${#SHELL_FILES[@]} == 0)); then
    echo "complexity check fail: no shell files discovered" >&2
    exit 1
fi

check_file_lines() {
    local file="$1"
    local limit="$2"
    local label="$3"
    local lines
    lines="$(wc -l < "$file")"
    if [[ "$lines" =~ ^[0-9]+$ ]] && ((lines > limit)); then
        echo "complexity check fail: ${label} ${file} has ${lines} lines (limit ${limit})" >&2
        fail=1
    fi
}

check_function_lines() {
    local file="$1"
    awk -v file="$file" -v max_lines="$MAX_FUNC_LINES" '
        function count_open(line, tmp) {
            tmp = line
            return gsub(/\{/, "{", tmp)
        }
        function count_close(line, tmp) {
            tmp = line
            return gsub(/\}/, "}", tmp)
        }
        BEGIN {
            in_fn = 0
            depth = 0
            bad = 0
            fn = ""
            start = 0
        }
        {
            if (!in_fn && match($0, /^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{/, m)) {
                in_fn = 1
                fn = m[1]
                start = NR
                depth = 0
            }
            if (in_fn) {
                depth += count_open($0)
                depth -= count_close($0)
                if (depth == 0) {
                    fn_lines = NR - start + 1
                    if (fn_lines > max_lines) {
                        printf "complexity check fail: %s:%d function %s has %d lines (limit %d)\n", file, start, fn, fn_lines, max_lines > "/dev/stderr"
                        bad = 1
                    }
                    in_fn = 0
                    fn = ""
                    start = 0
                }
            }
        }
        END {
            if (bad) {
                exit 3
            }
        }
    ' "$file" || fail=1
}

check_bats_test_lines() {
    local file="$1"
    awk -v file="$file" -v max_lines="$MAX_BATS_TEST_LINES" '
        function count_open(line, tmp) {
            tmp = line
            return gsub(/\{/, "{", tmp)
        }
        function count_close(line, tmp) {
            tmp = line
            return gsub(/\}/, "}", tmp)
        }
        BEGIN {
            in_test = 0
            depth = 0
            bad = 0
            test_name = ""
            start = 0
        }
        {
            if (!in_test && $0 ~ /^[[:space:]]*@test[[:space:]]+"/ && $0 ~ /\{[[:space:]]*$/) {
                in_test = 1
                test_name = $0
                start = NR
                depth = 0
            }
            if (in_test) {
                depth += count_open($0)
                depth -= count_close($0)
                if (depth == 0) {
                    test_lines = NR - start + 1
                    if (test_lines > max_lines) {
                        printf "complexity check fail: bats test in %s:%d has %d lines (limit %d)\n", file, start, test_lines, max_lines > "/dev/stderr"
                        bad = 1
                    }
                    in_test = 0
                    test_name = ""
                    start = 0
                }
            }
        }
        END {
            if (bad) {
                exit 3
            }
        }
    ' "$file" || fail=1
}

for file in "${SHELL_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    check_file_lines "$file" "$MAX_FILE_LINES" "shell file"
    check_function_lines "$file"
done

for file in "${BATS_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    check_file_lines "$file" "$MAX_BATS_FILE_LINES" "bats file"
    check_bats_test_lines "$file"
done

for file in "${POWERSHELL_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    check_file_lines "$file" "$MAX_PS1_FILE_LINES" "powershell file"
done

if ((fail != 0)); then
    exit 1
fi

echo "shell complexity check: ok"
