#!/usr/bin/env bats

@test "lint wiring includes bats and powershell quality gates" {
    run bash -eo pipefail -c '
    grep -Fq "command -v bats >/dev/null" ./Makefile
    grep -Fq "bash scripts/check-bats-quality.sh" ./Makefile
    grep -Fq "bash scripts/check-powershell-syntax.sh" ./Makefile
    grep -Fq "bash scripts/check-domain-data-consistency.sh" ./Makefile
    grep -Fq "\"\$SCRIPT_DIR/scripts/check-bats-quality.sh\"" ./tests/lint.sh
    grep -Fq "\"\$SCRIPT_DIR/scripts/check-powershell-syntax.sh\"" ./tests/lint.sh
    grep -Fq "\"\$SCRIPT_DIR/scripts/check-domain-data-consistency.sh\"" ./tests/lint.sh
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

@test "domain data consistency checker is wired and passes on current repo" {
    run bash -eo pipefail -c '
    grep -Fq "catalog.json" ./scripts/check-domain-data-consistency.sh
    grep -Fq "sni_pools.map" ./scripts/check-domain-data-consistency.sh
    grep -Fq "generate-domain-fallbacks.sh" ./scripts/check-domain-data-consistency.sh
    bash ./scripts/check-domain-data-consistency.sh
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"domain-data-check: ok"* ]]
}

@test "domain fallback generator reproduces committed files from catalog canon" {
    run bash -eo pipefail -c '
    tmpdir=$(mktemp -d)
    trap "rm -rf \"$tmpdir\"" EXIT
    bash ./scripts/generate-domain-fallbacks.sh --out-dir "$tmpdir"
    diff -u ./domains.tiers "$tmpdir/domains.tiers"
    diff -u ./sni_pools.map "$tmpdir/sni_pools.map"
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "legacy transport compatibility defaults live in dedicated contract module" {
    run bash -eo pipefail -c '
    grep -Fq "legacy_transport_contract.sh" ./modules/lib/globals_contract.sh
    grep -Fq "MUX_MODE" ./modules/lib/legacy_transport_contract.sh
    grep -Fq "GRPC_IDLE_TIMEOUT_MIN" ./modules/lib/legacy_transport_contract.sh
    ! grep -Fq "MUX_MODE=\"\${MUX_MODE:-off}\"" ./lib.sh
    echo ok
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "xray installer verifies sidecars from official release origin first" {
    run bash -eo pipefail -c '
    grep -Fq "install_xray_official_release_base()" ./modules/install/xray_runtime.sh
    grep -Fq "Скачиваем официальный SHA256" ./modules/install/xray_runtime.sh
    grep -Fq "Официальная minisign подпись недоступна" ./modules/install/xray_runtime.sh
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
