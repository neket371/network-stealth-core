#!/usr/bin/env bats

@test "version_lt returns true for lower version" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "1.0.0" "2.0.0" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "version_lt returns false for equal version" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "1.0.0" "1.0.0" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "version_lt returns false for higher version" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "3.0.0" "2.0.0" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "version_lt handles empty strings" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "" "1.0.0" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "version_lt treats prerelease as lower than stable" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "1.2.3-rc1" "1.2.3" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "version_lt accepts versions with v prefix" {
    run bash -eo pipefail -c 'source ./lib.sh; version_lt "v1.2.3" "v1.2.4" && echo "true" || echo "false"'
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "rand_between returns value in range" {
    run bash -eo pipefail -c '
    source ./lib.sh
    val=$(rand_between 10 20)
    [[ $val -ge 10 && $val -le 20 ]] && echo "ok" || echo "fail: $val"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rand_between handles min equals max" {
    run bash -eo pipefail -c 'source ./lib.sh; rand_between 5 5'
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "rand_between handles reversed min/max" {
    run bash -eo pipefail -c 'source ./lib.sh; rand_between 20 10'
    [ "$status" -eq 0 ]
    [ "$output" = "20" ]
}

@test "rand_between rejects modulo-bias tail when source range allows it" {
    run bash -eo pipefail -c '
    source ./lib.sh
    calls=0
    rand_u32() {
      calls=$((calls + 1))
      RAND_U32_MAX=9
      if [[ "$calls" -eq 1 ]]; then
        RAND_U32_VALUE=9
      else
        RAND_U32_VALUE=4
      fi
      echo "$RAND_U32_VALUE"
    }
    val=$(rand_between 0 5)
    [[ "$val" == "4" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "progress_bar handles zero total" {
    run bash -eo pipefail -c 'source ./lib.sh; progress_bar 0 0; echo "ok"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "progress_bar displays progress" {
    run bash -eo pipefail -c 'source ./lib.sh; progress_bar 5 10'
    [ "$status" -eq 0 ]
    [[ "$output" == *"50%"* ]]
}

@test "resolve_progress_mode uses plain mode for dumb terminals in auto mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PROGRESS_MODE="auto"
    TERM="dumb"
    resolve_progress_mode
  '
    [ "$status" -eq 0 ]
    [ "$output" = "plain" ]
}

@test "progress_bar plain mode keeps sequential line output" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PROGRESS_MODE="plain"
    progress_bar 1 4
    progress_bar 2 4
    [[ "$PROGRESS_LINE_OPEN" == "false" ]]
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"25%] 1/4"* ]]
    [[ "$output" == *"50%] 2/4"* ]]
}

@test "log closes active progress line" {
    run bash -eo pipefail -c '
    source ./lib.sh
    PROGRESS_MODE="bar"
    progress_bar 1 2
    [[ "$PROGRESS_LINE_OPEN" == "true" ]]
    log INFO "after-progress"
    [[ "$PROGRESS_LINE_OPEN" == "false" ]]
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"after-progress"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "validate_install_config accepts valid mux mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=5
    START_PORT=443
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
    echo "$MUX_MODE"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"on"* ]]
}

@test "validate_install_config falls back to tier_ru for invalid tier" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="invalid"
    NUM_CONFIGS=5
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier_ru"* ]]
}

@test "validate_install_config accepts http2 transport" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=5
    START_PORT=443
    TRANSPORT="http2"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=3
    MUX_CONCURRENCY_MAX=20
    SHORT_ID_BYTES_MIN=8
    SHORT_ID_BYTES_MAX=16
    validate_install_config
    echo "$TRANSPORT"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"http2"* ]]
}

@test "validate_install_config clamps weak short id length" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=5
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=3
    MUX_CONCURRENCY_MAX=20
    SHORT_ID_BYTES_MIN=2
    SHORT_ID_BYTES_MAX=8
    validate_install_config
    echo "$SHORT_ID_BYTES_MIN"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"8"* ]]
}

@test "ask_num_configs uses XRAY_NUM_CONFIGS in non-interactive mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    XRAY_NUM_CONFIGS=3
    NUM_CONFIGS=5
    ask_num_configs
    echo "$NUM_CONFIGS"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}

@test "ask_num_configs skips when reusing config" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    REUSE_EXISTING_CONFIG=true
    ask_num_configs
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "ask_domain_profile defaults to tier_ru in non-interactive mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    DOMAIN_TIER="tier_global_ms10"
    ask_domain_profile
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier_ru"* ]]
}

@test "ask_domain_profile accepts XRAY_DOMAIN_PROFILE override" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    XRAY_DOMAIN_PROFILE="global-50"
    DOMAIN_TIER="tier_ru"
    ask_domain_profile
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier_global_ms10"* ]]
}

@test "ask_domain_profile warns when reuse-config ignores requested profile" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    log() { printf "%s %s\n" "$1" "$2"; }
    REUSE_EXISTING_CONFIG=true
    DOMAIN_TIER="tier_ru"
    XRAY_DOMAIN_PROFILE="global-50"
    ask_domain_profile
    echo "tier=$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"игнорируется"* ]]
    [[ "$output" == *"tier=tier_ru"* ]]
}

@test "ask_domain_profile accepts legacy global-ms10 alias with compatibility warning" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    XRAY_DOMAIN_PROFILE="global-ms10"
    DOMAIN_TIER="tier_ru"
    ask_domain_profile
    echo "$DOMAIN_TIER"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy-алиасом"* ]]
    [[ "$output" == *"tier_global_ms10"* ]]
}

@test "ask_domain_profile marks auto mode for ru-auto alias" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    XRAY_DOMAIN_PROFILE="ru-auto"
    DOMAIN_TIER="tier_global_ms10"
    ask_domain_profile
    echo "${DOMAIN_TIER}|${AUTO_PROFILE_MODE}"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier_ru|true"* ]]
}

@test "ask_num_configs auto profile chooses default for tier_ru" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    AUTO_PROFILE_MODE=true
    DOMAIN_TIER="tier_ru"
    XRAY_NUM_CONFIGS=""
    ask_num_configs
    echo "NUM=$NUM_CONFIGS"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"NUM=5"* ]]
}

@test "ask_num_configs auto profile chooses default for tier_global_ms10" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    AUTO_PROFILE_MODE=true
    DOMAIN_TIER="tier_global_ms10"
    XRAY_NUM_CONFIGS=""
    ask_num_configs
    echo "NUM=$NUM_CONFIGS"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"NUM=10"* ]]
}

@test "ask_num_configs fails in non-interactive mode without explicit value" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    ask_num_configs
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"--num-configs <1-100>"* ]]
}

@test "ask_num_configs enforces tier_global_ms10 limit in non-interactive mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./install.sh
    NON_INTERACTIVE=true
    DOMAIN_TIER="tier_global_ms10"
    XRAY_NUM_CONFIGS=11
    ask_num_configs
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"1-10"* ]]
}

@test "resolve_paths sets default paths when dirs are writable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    NON_INTERACTIVE=true
    _try_file_path() { return 0; }
    _try_dir() { return 0; }
    resolve_paths >/dev/null 2>&1
    echo "$XRAY_BIN"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"/xray"* ]]
}

@test "resolve_paths fails in non-interactive mode when paths are not writable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    NON_INTERACTIVE=true
    _try_file_path() { return 1; }
    _try_dir() { return 1; }
    resolve_paths
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Проверка системных путей завершилась с ошибками"* ]]
}

@test "_try_dir succeeds for /tmp" {
    run bash -eo pipefail -c '
    source ./lib.sh
    _try_dir /tmp && echo "ok" || echo "fail"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "_try_dir fails for non-writable path" {
    run bash -eo pipefail -c '
    source ./lib.sh
    _try_dir /proc/nonexistent 2>/dev/null && echo "ok" || echo "fail"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail"* ]]
}

@test "validate_install_config rejects zero configs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=0
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
  '
    [ "$status" -ne 0 ]
}

@test "validate_install_config rejects more than 100 configs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_ru"
    NUM_CONFIGS=101
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
  '
    [ "$status" -ne 0 ]
}

@test "validate_install_config accepts 10 configs for tier_global_ms10" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_global_ms10"
    NUM_CONFIGS=10
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validate_install_config rejects more than 10 configs for tier_global_ms10" {
    run bash -eo pipefail -c '
    source ./lib.sh
    DOMAIN_TIER="tier_global_ms10"
    NUM_CONFIGS=11
    START_PORT=443
    TRANSPORT="grpc"
    MUX_MODE="on"
    MUX_CONCURRENCY_MIN=6
    MUX_CONCURRENCY_MAX=12
    validate_install_config
  '
    [ "$status" -ne 0 ]
}

@test "count_listening_ports returns listening and expected counts" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    port_is_listening() {
        case "$1" in
            444 | 446) return 0 ;;
            *) return 1 ;;
        esac
    }
    read -r listening expected < <(count_listening_ports 444 "" 445 446)
    echo "${listening}/${expected}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "2/3" ]
}

@test "verify_ports_listening_after_start fails when only part of IPv4 ports listen" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    PORTS=(444 445)
    HAS_IPV6=false
    port_is_listening() {
        [[ "$1" == "444" ]]
    }
    sleep() { :; }
    systemctl_available() { return 0; }
    systemd_running() { return 0; }
    verify_ports_listening_after_start
  '
    [ "$status" -ne 0 ]
    [[ "$output" == *"1/2"* ]]
}

@test "verify_ports_listening_after_start skips check when systemd is unavailable" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    PORTS=(444 445)
    HAS_IPV6=false
    systemctl_available() { return 1; }
    systemd_running() { return 1; }
    verify_ports_listening_after_start
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"пропущена"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "verify_ports_listening_after_start succeeds when all IPv4 ports listen" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    PORTS=(444 445)
    HAS_IPV6=false
    port_is_listening() { return 0; }
    sleep() { :; }
    verify_ports_listening_after_start
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}
