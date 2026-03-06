#!/usr/bin/env bats

@test "generate_inbound_json uses xhttp network by default" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "test-uuid" "yandex.ru:443" "yandex.ru" "privkey" "abcd" "chrome" "/edge/api/demo" 30 60 20)
    net=$(echo "$json" | jq -r ".streamSettings.network")
    path=$(echo "$json" | jq -r ".streamSettings.xhttpSettings.path")
    echo "${net}:${path}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "xhttp:/edge/api/demo" ]
}

@test "generate_inbound_json keeps grpc legacy mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "test-uuid" "yandex.ru:443" "yandex.ru" "privkey" "abcd" "chrome" "my.api.v1.Service" 30 60 20 "grpc" "my.api.v1.Service")
    echo "$json" | jq -r ".streamSettings.grpcSettings.serviceName"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "my.api.v1.Service" ]
}

@test "generate_inbound_json supports http2 legacy mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "test-uuid" "yandex.ru:443" "[\"yandex.ru\"]" "privkey" "abcd" "chrome" "my.api.v1.Service" 30 60 20 "http2" "/my/api/v1/Service")
    net=$(echo "$json" | jq -r ".streamSettings.network")
    path=$(echo "$json" | jq -r ".streamSettings.httpSettings.path")
    echo "${net}:${path}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "h2:/my/api/v1/Service" ]
}

@test "build_inbound_profile_for_domain generates xhttp path for xhttp mode" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    TRANSPORT="xhttp"
    SKIP_REALITY_CHECK=true
    declare -A SNI_POOLS
    declare -A GRPC_SERVICES
    SNI_POOLS["yandex.ru"]="yandex.ru"
    declare -a fp_pool=("chrome")
    build_inbound_profile_for_domain "yandex.ru" fp_pool
    [[ "$PROFILE_TRANSPORT_ENDPOINT" == /* ]]
    echo "${PROFILE_FP}|${PROFILE_DEST}"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "chrome|yandex.ru:443" ]
}

@test "generate_profile_inbound_json uses prepared xhttp profile fields" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    TRANSPORT="xhttp"
    SKIP_REALITY_CHECK=true
    declare -A SNI_POOLS
    declare -A GRPC_SERVICES
    SNI_POOLS["yandex.ru"]="yandex.ru"
    declare -a fp_pool=("chrome")
    build_inbound_profile_for_domain "yandex.ru" fp_pool
    json=$(generate_profile_inbound_json 443 "test-uuid" "privkey" "abcd")
    net=$(echo "$json" | jq -r ".streamSettings.network")
    path=$(echo "$json" | jq -r ".streamSettings.xhttpSettings.path")
    echo "${net}:${path}"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == xhttp:/* ]]
}
