#!/usr/bin/env bats

@test "generate_inbound_json produces valid JSON for xhttp" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "test-uuid" "example.com:443" "example.com" \
      "privkey" "abcd1234" "chrome" "/edge/api/demo" 30 60 15)
    echo "$json" | jq -e .port
  '
    [ "$status" -eq 0 ]
    [ "$output" = "443" ]
}

@test "generate_inbound_json xhttp includes path" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "uuid" "d.com:443" "d.com" \
      "pk" "sid" "chrome" "/edge/api/demo" 30 45 10)
    echo "$json" | jq -r .streamSettings.xhttpSettings.path
  '
    [ "$status" -eq 0 ]
    [ "$output" = "/edge/api/demo" ]
}

@test "generate_inbound_json includes reality settings" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "my-uuid" "target.com:443" "target.com" \
      "myprivkey" "aabb" "chrome" "/edge/api/demo" 30 60 15)
    echo "$json" | jq -r .streamSettings.realitySettings.privateKey
  '
    [ "$status" -eq 0 ]
    [ "$output" = "myprivkey" ]
}

@test "generate_inbound_json includes bbr congestion in sockopt" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_inbound_json 443 "uuid" "d.com:443" "d.com" \
      "pk" "sid" "chrome" "/edge/api/demo" 30 45 10)
    echo "$json" | jq -r .streamSettings.sockopt.tcpCongestion
  '
    [ "$status" -eq 0 ]
    [ "$output" = "bbr" ]
}

@test "generate_outbounds_json produces valid JSON" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    MUX_ENABLED=false
    MUX_CONCURRENCY=0
    json=$(generate_outbounds_json)
    echo "$json" | jq -e ".[0].protocol"
  '
    [ "$status" -eq 0 ]
    [ "$output" = '"freedom"' ]
}

@test "generate_outbounds_json does not emit server-side mux field" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    MUX_ENABLED=true
    MUX_CONCURRENCY=16
    json=$(generate_outbounds_json)
    echo "$json" | jq -r ".[0] | has(\"mux\")"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "generate_routing_json blocks private IPs" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    json=$(generate_routing_json)
    echo "$json" | jq -e ".rules[0].ip[0]"
  '
    [ "$status" -eq 0 ]
    [ "$output" = '"geoip:private"' ]
}

@test "check_xray_version_for_config_generation warns on untested major transport format" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    tmp_bin=$(mktemp)
    trap "rm -f \"$tmp_bin\"" EXIT
    cat > "$tmp_bin" <<EOF
#!/usr/bin/env bash
echo "Xray 26.1.0"
EOF
    chmod +x "$tmp_bin"
    XRAY_BIN="$tmp_bin"
    log() { echo "$*"; }
    check_xray_version_for_config_generation
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"26.1.0"* ]]
}
