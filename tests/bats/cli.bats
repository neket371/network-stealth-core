#!/usr/bin/env bats

@test "parse_bool handles true-ish values" {
    local value
    for value in 1 true yes y on; do
        run bash -eo pipefail -c "source ./lib.sh; parse_bool \"$value\" false"
        [ "$status" -eq 0 ]
        [ "$output" = "true" ]
    done
}

@test "parse_bool handles false-ish values" {
    local value
    for value in 0 false no n off; do
        run bash -eo pipefail -c "source ./lib.sh; parse_bool \"$value\" true"
        [ "$status" -eq 0 ]
        [ "$output" = "false" ]
    done
}

@test "normalize_domain_tier accepts underscore alias and canonicalizes value" {
    run bash -eo pipefail -c 'source ./lib.sh; normalize_domain_tier "tier_global_ms10"'
    [ "$status" -eq 0 ]
    [ "$output" = "tier_global_ms10" ]
}

@test "normalize_domain_tier accepts ru-auto alias" {
    run bash -eo pipefail -c 'source ./lib.sh; normalize_domain_tier "ru-auto"'
    [ "$status" -eq 0 ]
    [ "$output" = "tier_ru" ]
}

@test "normalize_domain_tier accepts global-50-auto alias" {
    run bash -eo pipefail -c 'source ./lib.sh; normalize_domain_tier "global-50-auto"'
    [ "$status" -eq 0 ]
    [ "$output" = "tier_global_ms10" ]
}

@test "normalize_domain_tier keeps legacy global-ms10-auto alias compatibility" {
    run bash -eo pipefail -c 'source ./lib.sh; normalize_domain_tier "global-ms10-auto"'
    [ "$status" -eq 0 ]
    [ "$output" = "tier_global_ms10" ]
}

@test "default runtime flags require explicit non-interactive confirmation" {
    run bash -eo pipefail -c 'source ./lib.sh; echo "${ASSUME_YES}:${NON_INTERACTIVE}"'
    [ "$status" -eq 0 ]
    [ "$output" = "false:false" ]
}

@test "parse_args --yes enables non-interactive confirmation mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args --yes uninstall
    echo "${ASSUME_YES}:${NON_INTERACTIVE}:${ACTION}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "true:true:uninstall" ]
}

@test "parse_args --non-interactive enables non-interactive confirmation mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args --non-interactive uninstall
    echo "${ASSUME_YES}:${NON_INTERACTIVE}:${ACTION}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "true:true:uninstall" ]
}

@test "parse_args accepts --domain-check-parallelism" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --domain-check-parallelism=24
    echo "${ACTION}:${DOMAIN_CHECK_PARALLELISM}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "install:24" ]
}

@test "parse_args accepts install-first long options with values" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --num-configs 3 --non-interactive --yes
    apply_runtime_overrides
    echo "${ACTION}:${NUM_CONFIGS}:${NON_INTERACTIVE}:${ASSUME_YES}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "install:3:true:true" ]
}

@test "parse_args accepts --require-minisign and --allow-no-systemd" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args --require-minisign --allow-no-systemd install
    apply_runtime_overrides
    echo "${REQUIRE_MINISIGN}:${ALLOW_NO_SYSTEMD}:${ACTION}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "true:true:install" ]
}

@test "parse_args accepts rollback long option with optional directory" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args --rollback /tmp/session
    echo "${ACTION}:${ROLLBACK_DIR}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "rollback:/tmp/session" ]
}

@test "parse_args rejects missing long-option value when next token is a flag" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --server-ip --verbose
  '
    [ "$status" -eq 1 ]
    [[ "$output" == *"Не указан параметр для --server-ip"* ]]
}

@test "parse_args rejects missing long-option value at end of argv" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args install --config
  '
    [ "$status" -eq 1 ]
    [[ "$output" == *"Не указан параметр для --config"* ]]
}

@test "parse_args rejects unknown long option" {
    run bash -eo pipefail -c '
    source ./lib.sh
    parse_args --definitely-unknown install
  '
    [ "$status" -eq 1 ]
    [[ "$output" == *"Неизвестный аргумент: --definitely-unknown"* ]]
}

@test "trim_ws strips leading and trailing spaces" {
    run bash -eo pipefail -c 'source ./lib.sh; trim_ws "  hello world  "'
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "split_list splits comma-separated values" {
    run bash -eo pipefail -c 'source ./lib.sh; split_list "a,b"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
}

@test "split_list splits space-separated values" {
    run bash -eo pipefail -c 'source ./lib.sh; split_list "a b"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
}

@test "split_list splits mixed comma and space separators" {
    run bash -eo pipefail -c 'source ./lib.sh; split_list "a, b c"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
    [ "${lines[2]}" = "c" ]
}

@test "get_query_param extracts value by key" {
    run bash -eo pipefail -c 'source ./lib.sh; get_query_param "a=1&b=2" "b"'
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "get_query_param decodes url-encoded value" {
    run bash -eo pipefail -c 'source ./lib.sh; get_query_param "a=1&pbk=abc%2B123%2F%3D&sid=s%23id" "pbk"'
    [ "$status" -eq 0 ]
    [ "$output" = "abc+123/=" ]
}

@test "sanitize_log_message redacts VLESS links and identifiers" {
    run bash -eo pipefail -c '
    source ./lib.sh
    secret_uuid="110fdea4-ddfe-4f83-bc44-ca4a63b9079a"
    input="vless://${secret_uuid}@1.1.1.1:444?pbk=abc123&sid=deadbeef#cfg uuid=${secret_uuid}"
    out=$(sanitize_log_message "$input")

    [[ "$out" == *"VLESS-REDACTED"* ]]
    [[ "$out" == *"UUID-REDACTED"* ]]
    [[ "$out" != *"vless://"* ]]
    [[ "$out" != *"$secret_uuid"* ]]
    [[ "$out" != *"pbk=abc123"* ]]
    [[ "$out" != *"sid=deadbeef"* ]]
    echo "ok"
  '
    if [[ "$status" -ne 0 ]]; then
        echo "debug-status=$status"
        echo "$output"
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "debug_file writes sanitized content into install log" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    INSTALL_LOG="$tmp"
    secret_uuid="110fdea4-ddfe-4f83-bc44-ca4a63b9079a"
    debug_file "leak-test vless://${secret_uuid}@1.1.1.1:444?pbk=abc123&sid=deadbeef"

    grep -q "VLESS-REDACTED" "$tmp"
    ! grep -q "vless://" "$tmp"
    ! grep -q "$secret_uuid" "$tmp"
    ! grep -q "pbk=abc123" "$tmp"
    ! grep -q "sid=deadbeef" "$tmp"
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "setup_logging avoids mktemp -u race pattern" {
    run bash -eo pipefail -c '
    ! grep -q "mktemp -u .*xray-log" ./lib.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "install sysctl profile sets bbr congestion control" {
    run bash -eo pipefail -c '
    grep -q "^net\\.ipv4\\.tcp_congestion_control = bbr$" ./install.sh
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
