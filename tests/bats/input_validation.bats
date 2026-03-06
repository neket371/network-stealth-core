#!/usr/bin/env bats

# ==================== is_valid_domain ====================

@test "is_valid_domain accepts valid domain" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "example.com"'
    [ "$status" -eq 0 ]
}

@test "is_valid_domain accepts subdomain" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "sub.example.com"'
    [ "$status" -eq 0 ]
}

@test "is_valid_domain accepts deep subdomain" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "a.b.c.d.example.com"'
    [ "$status" -eq 0 ]
}

@test "is_valid_domain accepts hyphenated domain" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "my-site.example.com"'
    [ "$status" -eq 0 ]
}

@test "is_valid_domain rejects empty string" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain ""'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects no TLD" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "localhost"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects consecutive dots" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "bad..domain.com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects leading dot" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain ".example.com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects trailing dot" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "example.com."'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects leading hyphen" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "-example.com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects special characters" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "exam;ple.com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects command injection" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "example.com;rm -rf /"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects spaces" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "example .com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain rejects over 253 chars" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "$(printf "a%.0s" {1..250}).com"'
    [ "$status" -eq 1 ]
}

# ==================== is_valid_port ====================

@test "is_valid_port accepts 443" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port 443'
    [ "$status" -eq 0 ]
}

@test "is_valid_port accepts 1" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port 1'
    [ "$status" -eq 0 ]
}

@test "is_valid_port accepts 65535" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port 65535'
    [ "$status" -eq 0 ]
}

@test "is_valid_port rejects 0" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port 0'
    [ "$status" -eq 1 ]
}

@test "is_valid_port rejects 65536" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port 65536'
    [ "$status" -eq 1 ]
}

@test "is_valid_port rejects non-numeric" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port "abc"'
    [ "$status" -eq 1 ]
}

@test "is_valid_port rejects negative" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_port "-1"'
    [ "$status" -eq 1 ]
}

# ==================== is_valid_ipv4 ====================

@test "is_valid_ipv4 accepts valid IP" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "192.168.1.1"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv4 accepts 0.0.0.0" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "0.0.0.0"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv4 accepts 255.255.255.255" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "255.255.255.255"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv4 rejects too few octets" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "192.168.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 rejects too many octets" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "192.168.1.1.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 rejects octet over 255" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "192.168.1.256"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 rejects non-numeric octet" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "192.168.a.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 rejects leading zeros (octal bypass)" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "010.0.0.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 rejects 0377.0.0.1 (octal 255)" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "0377.0.0.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv4 accepts single zero octets" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv4 "10.0.0.1"'
    [ "$status" -eq 0 ]
}

# ==================== is_valid_domain (label length) ====================

@test "is_valid_domain rejects label over 63 chars" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "$(printf "a%.0s" {1..64}).com"'
    [ "$status" -eq 1 ]
}

@test "is_valid_domain accepts label at exactly 63 chars" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_domain "$(printf "a%.0s" {1..63}).com"'
    [ "$status" -eq 0 ]
}

# ==================== load_map_file key validation ====================

@test "load_map_file rejects key with shell metacharacters" {
    run bash -eo pipefail -c '
        source ./lib.sh
        declare -A testmap=()
        tmpfile=$(mktemp)
        echo "valid-key.com=value1" > "$tmpfile"
        echo "bad];key=value2" >> "$tmpfile"
        echo "good.key=value3" >> "$tmpfile"
        load_map_file "$tmpfile" "testmap"
        rm -f "$tmpfile"
        echo "${#testmap[@]}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "load_map_file accepts valid domain-like keys" {
    run bash -eo pipefail -c '
        source ./lib.sh
        declare -A testmap=()
        tmpfile=$(mktemp)
        echo "example.com=value1" > "$tmpfile"
        echo "sub-domain.test.org=value2" >> "$tmpfile"
        load_map_file "$tmpfile" "testmap"
        rm -f "$tmpfile"
        echo "${testmap[example.com]}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "value1" ]
}

@test "load_map_file fails on unsafe value characters instead of silent sanitization" {
    run bash -eo pipefail -c '
        source ./lib.sh
        declare -A testmap=()
        tmpfile=$(mktemp)
        echo "example.com=value1" > "$tmpfile"
        echo "bad.com=value;rm -rf /" >> "$tmpfile"
        if load_map_file "$tmpfile" "testmap"; then
            rm -f "$tmpfile"
            echo "unexpected-success"
            exit 1
        fi
        rm -f "$tmpfile"
        echo "${testmap[example.com]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"value1"* ]]
}

# ==================== is_valid_ipv6 ====================

@test "is_valid_ipv6 accepts full address" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 accepts compressed loopback" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "::1"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 accepts trailing compression" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "fe80::"'
    [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 rejects plain text" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "not-an-ip"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv6 rejects ipv4 address" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "192.168.1.1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv6 rejects triple-colon forms" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "2001:::1"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv6 rejects leading single-colon form" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 ":1:2:3:4:5:6:7"'
    [ "$status" -eq 1 ]
}

@test "is_valid_ipv6 rejects trailing single-colon form" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_ipv6 "1:2:3:4:5:6:7:"'
    [ "$status" -eq 1 ]
}

# ==================== is_valid_grpc_service_name ====================

@test "is_valid_grpc_service_name accepts dotted service name" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_grpc_service_name "com.vk.api.v1.GatewayService"'
    [ "$status" -eq 0 ]
}

@test "is_valid_grpc_service_name rejects invalid segment start" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_grpc_service_name "com.2vk.api.v1.GatewayService"'
    [ "$status" -eq 1 ]
}

@test "is_valid_xhttp_path accepts normalized secret path" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_xhttp_path "/edge/api/demo-01"'
    [ "$status" -eq 0 ]
}

@test "is_valid_xhttp_path rejects query string" {
    run bash -eo pipefail -c 'source ./lib.sh; is_valid_xhttp_path "/edge/api/demo?bad=1"'
    [ "$status" -eq 1 ]
}
