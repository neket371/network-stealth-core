#!/usr/bin/env bats

@test "lint wiring includes bats and powershell quality gates" {
    run bash -eo pipefail -c '
    grep -Fq "command -v bats >/dev/null" ./Makefile
    grep -Fq "bash scripts/check-bats-quality.sh" ./Makefile
    grep -Fq "bash scripts/check-powershell-syntax.sh" ./Makefile
    grep -Fq "\"\$SCRIPT_DIR/scripts/check-bats-quality.sh\"" ./tests/lint.sh
    grep -Fq "\"\$SCRIPT_DIR/scripts/check-powershell-syntax.sh\"" ./tests/lint.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "tests lint fast mode tracks bats and powershell files" {
    run bash -eo pipefail -c '
    grep -Fq "*.bats)" ./tests/lint.sh
    grep -Fq "*.ps1)" ./tests/lint.sh
    grep -Fq "BATS_FILES" ./tests/lint.sh
    grep -Fq "PS1_FILES" ./tests/lint.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "complexity gate includes bats and powershell scopes" {
    run bash -eo pipefail -c '
    grep -Fq "MAX_BATS_FILE_LINES" ./scripts/check-shell-complexity.sh
    grep -Fq "MAX_BATS_TEST_LINES" ./scripts/check-shell-complexity.sh
    grep -Fq "MAX_PS1_FILE_LINES" ./scripts/check-shell-complexity.sh
    grep -Fq "tests/bats" ./scripts/check-shell-complexity.sh
    grep -Fq "check_bats_test_lines" ./scripts/check-shell-complexity.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "dead-function checker uses shared candidate scan" {
    run bash -eo pipefail -c '
    grep -Fq "combined_pattern" ./scripts/check-dead-functions.sh
    grep -Fq "matches_tmp" ./scripts/check-dead-functions.sh
    grep -Fq "def_location" ./scripts/check-dead-functions.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "atomic_write restricts /usr/local to managed subpaths" {
    run bash -eo pipefail -c '
    source ./lib.sh
    log() { printf "%s\n" "$*"; }
    result=$({ printf "x\n" | atomic_write /usr/local/lib/xray-reality-test 0644; } 2>&1 || true)
    [[ "$result" == *"вне разрешённых директорий"* ]]
    grep -Fq '\''"/usr/local/bin"'\'' ./lib.sh
    grep -Fq '\''"/usr/local/share/xray-reality"'\'' ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "check_update_flow degrades gracefully when version comparator is unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./service.sh
    tmpbin=$(mktemp)
    trap "rm -f \"$tmpbin\"" EXIT
    cat > "$tmpbin" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "Xray 1.2.3"
EOF
    chmod +x "$tmpbin"
    XRAY_BIN="$tmpbin"
    curl_fetch_text_allowlist() {
      printf "%s\n" "{\"tag_name\":\"v1.2.4\"}"
    }
    unset -f version_lt
    result=$(check_update_flow)
    [[ "$result" == *"Текущая версия Xray:"* ]]
    [[ "$result" == *"Последняя версия Xray:"* ]]
    [[ "$result" == *"Не удалось сравнить версии автоматически"* ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
