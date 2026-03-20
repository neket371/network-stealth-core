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
