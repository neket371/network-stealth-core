#!/usr/bin/env bats

@test "load_tier_domains_from_file loads tier_ru domains" {
    run bash -eo pipefail -c 'source ./lib.sh; load_tier_domains_from_file "domains.tiers" "tier_ru"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"yandex.ru"* ]]
    [[ "$output" == *"vk.com"* ]]
}

@test "load_tier_domains_from_file loads tier_global_ms10 domains" {
    run bash -eo pipefail -c 'source ./lib.sh; load_tier_domains_from_file "domains.tiers" "tier_global_ms10"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"microsoft.com"* ]]
    [[ "$output" == *"microsoftonline.com"* ]]
}

@test "load_tier_domains_from_file returns empty for unknown tier" {
    run bash -eo pipefail -c 'source ./lib.sh; load_tier_domains_from_file "domains.tiers" "nonexistent"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "setup_domains returns non-zero so caller can handle errors" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    REUSE_EXISTING_CONFIG=false
    XRAY_TIERS_FILE="/nonexistent/path"
    XRAY_DOMAIN_CATALOG_FILE="/nonexistent/catalog.json"

    if setup_domains; then
      echo "unexpected-success"
    else
      echo "handled"
    fi
    echo "after"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "handled" ]
    [ "${lines[1]}" = "after" ]
}

@test "setup_domains uses catalog-first xhttp tier metadata without tiers or sni map files" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    REUSE_EXISTING_CONFIG=false
    DOMAIN_CHECK=false
    TRANSPORT=xhttp
    DOMAIN_TIER=tier_ru
    NUM_CONFIGS=1
    XRAY_DOMAIN_CATALOG_FILE="./data/domains/catalog.json"
    XRAY_TIERS_FILE="/nonexistent/path"
    XRAY_SNI_POOLS_FILE="/nonexistent/sni_pools.map"
    setup_domains
    echo "tier=${DOMAIN_TIER}"
    echo "catalog=${DOMAIN_TIER_USES_CATALOG}"
    echo "domains=${#AVAILABLE_DOMAINS[@]}"
    echo "sni=$(printf "%s" "${SNI_POOLS[yandex.ru]}")"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "tier=tier_ru" ]
    [ "${lines[1]}" = "catalog=true" ]
    [[ "${lines[2]}" == domains=* ]]
    [[ "${lines[3]}" == *"api.yandex.ru"* ]]
}

@test "setup_domains still requires legacy endpoint seeds for grpc migration coverage" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    REUSE_EXISTING_CONFIG=false
    DOMAIN_CHECK=false
    TRANSPORT=grpc
    DOMAIN_TIER=tier_ru
    NUM_CONFIGS=1
    XRAY_DOMAIN_CATALOG_FILE="./data/domains/catalog.json"
    XRAY_TIERS_FILE="/nonexistent/path"
    XRAY_SNI_POOLS_FILE="/nonexistent/sni_pools.map"
    XRAY_TRANSPORT_ENDPOINTS_FILE="/nonexistent/transport_endpoints.map"
    setup_domains
  '
    [ "$status" -ne 0 ]
}

@test "tier_global_ms10 has 50 unique domains and full map coverage" {
    run bash -eo pipefail -c '
    source ./lib.sh
    mapfile -t domains < <(load_tier_domains_from_file "domains.tiers" "tier_global_ms10")
    declare -A SNI=()
    declare -A ENDPOINTS=()
    load_map_file "sni_pools.map" SNI
    load_map_file "transport_endpoints.map" ENDPOINTS

    echo "domains=${#domains[@]}"
    unique_count=$(printf "%s\n" "${domains[@]}" | sort -u | wc -l | tr -d " ")
    echo "unique=${unique_count}"

    missing=0
    for d in "${domains[@]}"; do
      [[ -n "${SNI[$d]:-}" ]] || missing=$((missing + 1))
      [[ -n "${ENDPOINTS[$d]:-}" ]] || missing=$((missing + 1))
    done
    echo "missing=${missing}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "domains=50" ]
    [ "${lines[1]}" = "unique=50" ]
    [ "${lines[2]}" = "missing=0" ]
}

@test "load_domain_list splits comma values" {
    run bash -eo pipefail -c 'source ./lib.sh; load_domain_list "a.com,b.com,c.com"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "b.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "load_domain_list trims whitespace around values" {
    run bash -eo pipefail -c 'source ./lib.sh; load_domain_list "  a.com ,  b.com  , c.com  "'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "b.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "load_domain_list splits mixed comma and space separators" {
    run bash -eo pipefail -c 'source ./lib.sh; load_domain_list "a.com, b.com c.com"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "b.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "load_domains_from_file trims values and skips comments" {
    run bash -eo pipefail -c '
    source ./lib.sh
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp" <<EOF
  a.com

  # comment
    b.com
c.com  
EOF
    load_domains_from_file "$tmp"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "b.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "detect_reality_dest accepts CONNECTED marker from openssl output" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    timeout() { printf "CONNECTED(00000003)\n"; }
    detect_reality_dest "example.com"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "443" ]
}

@test "detect_reality_dest accepts CONNECTION ESTABLISHED marker from openssl -brief output" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    timeout() { printf "CONNECTION ESTABLISHED\n"; }
    detect_reality_dest "example.com"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "443" ]
}

@test "load_map_file parses sni_pools.map" {
    run bash -eo pipefail -c '
    source ./lib.sh
    declare -A MAP=()
    load_map_file "sni_pools.map" MAP
    echo "${MAP[yandex.ru]}"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"api.yandex.ru"* ]]
}

@test "load_map_file parses transport_endpoints.map" {
    run bash -eo pipefail -c '
    source ./lib.sh
    declare -A MAP=()
    load_map_file "transport_endpoints.map" MAP
    echo "${MAP[vk.com]}"
  '
    [ "$status" -eq 0 ]
    [[ "$output" == *"com.vk.api.v1.GatewayService"* ]]
}

@test "load_map_file handles missing file gracefully" {
    run bash -eo pipefail -c '
    source ./lib.sh
    declare -A MAP=()
    load_map_file "/nonexistent/path" MAP
    echo "ok"
  '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "rank_domains_by_health sorts domains by score" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    DOMAIN_HEALTH_RANKING=true
    DOMAIN_HEALTH_FILE=$(mktemp)
    cat > "$DOMAIN_HEALTH_FILE" <<EOF
{"domains":{"a.com":{"score":1},"b.com":{"score":9},"c.com":{"score":-2}}}
EOF
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    rank_domains_by_health
    printf "%s\n" "${AVAILABLE_DOMAINS[@]}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "b.com" ]
    [ "${lines[1]}" = "a.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "rank_domains_by_health keeps order when disabled" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    DOMAIN_HEALTH_RANKING=false
    DOMAIN_HEALTH_FILE=$(mktemp)
    cat > "$DOMAIN_HEALTH_FILE" <<EOF
{"domains":{"a.com":{"score":1},"b.com":{"score":9},"c.com":{"score":-2}}}
EOF
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    rank_domains_by_health
    printf "%s\n" "${AVAILABLE_DOMAINS[@]}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "b.com" ]
    [ "${lines[2]}" = "c.com" ]
}

@test "prioritize_cycle_for_field_conditions prefers lower family penalty over raw priority" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    summary_file=$(mktemp)
    trap "rm -f \"$summary_file\"" EXIT
    cat > "$summary_file" <<EOF
{"provider_family_stats":[
  {"provider_family":"weakfam","field_penalty":80},
  {"provider_family":"strongfam","field_penalty":0}
]}
EOF
    MEASUREMENTS_SUMMARY_FILE="$summary_file"
    declare -gA DOMAIN_PROVIDER_FAMILIES=(
      ["bad.com"]="weakfam"
      ["good.com"]="strongfam"
    )
    declare -gA DOMAIN_PRIORITY_MAP=(
      ["bad.com"]="10"
      ["good.com"]="0"
    )
    declare -gA DOMAIN_RISK_MAP=(
      ["bad.com"]="normal"
      ["good.com"]="normal"
    )
    cycle=("bad.com" "good.com")
    load_provider_family_field_penalties
    prioritize_cycle_for_field_conditions cycle ranked ""
    printf "%s\n" "${ranked[@]}"
   '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "good.com" ]
    [ "${lines[1]}" = "bad.com" ]
}

@test "prioritize_cycle_for_field_conditions avoids current primary family in spare ordering" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    summary_file=$(mktemp)
    trap "rm -f \"$summary_file\"" EXIT
    cat > "$summary_file" <<EOF
{"current_primary_family":"bluefam","operator_recommendation":"promote-spare","provider_family_stats":[]}
EOF
    MEASUREMENTS_SUMMARY_FILE="$summary_file"
    declare -gA DOMAIN_PROVIDER_FAMILIES=(
      ["same-family.com"]="bluefam"
      ["independent.com"]="greenfam"
    )
    declare -gA DOMAIN_PRIORITY_MAP=(
      ["same-family.com"]="10"
      ["independent.com"]="0"
    )
    declare -gA DOMAIN_RISK_MAP=(
      ["same-family.com"]="normal"
      ["independent.com"]="normal"
    )
    load_provider_family_field_penalties
    cycle=("same-family.com" "independent.com")
    prioritize_cycle_for_field_conditions cycle ranked "" "$(domain_rotation_family_to_avoid "")"
    printf "%s\n" "${ranked[@]}"
   '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "independent.com" ]
    [ "${lines[1]}" = "same-family.com" ]
}

@test "tier_ru has 150 unique domains and full map coverage" {
    run bash -eo pipefail -c '
    source ./lib.sh
    mapfile -t domains < <(load_tier_domains_from_file "domains.tiers" "tier_ru")
    declare -A SNI=()
    declare -A ENDPOINTS=()
    load_map_file "sni_pools.map" SNI
    load_map_file "transport_endpoints.map" ENDPOINTS

    echo "domains=${#domains[@]}"
    unique_count=$(printf "%s\n" "${domains[@]}" | sort -u | wc -l | tr -d " ")
    echo "unique=${unique_count}"

    missing=0
    for d in "${domains[@]}"; do
      [[ -n "${SNI[$d]:-}" ]] || missing=$((missing + 1))
      [[ -n "${ENDPOINTS[$d]:-}" ]] || missing=$((missing + 1))
    done
    echo "missing=${missing}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "domains=150" ]
    [ "${lines[1]}" = "unique=150" ]
    [ "${lines[2]}" = "missing=0" ]
}

@test "build_domain_plan avoids repeats before pool exhaustion" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com" "d.com")
    SPIDER_MODE=true
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="a.com"
    PRIMARY_ADAPTIVE_TOP_N=3
    build_domain_plan 4 true

    echo "total=${#DOMAIN_SELECTION_PLAN[@]}"
    unique_count=$(printf "%s\n" "${DOMAIN_SELECTION_PLAN[@]}" | sort -u | wc -l | tr -d " ")
    echo "unique=${unique_count}"
    echo "first=${DOMAIN_SELECTION_PLAN[0]}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "total=4" ]
    [ "${lines[1]}" = "unique=4" ]
    [ "${lines[2]}" = "first=a.com" ]
}

@test "select_primary_domain uses [priority] section when present" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    tiers_tmp=$(mktemp)
    trap "rm -f \"$tiers_tmp\"" EXIT
    cat > "$tiers_tmp" <<EOF
[tier_ru]
a.com
b.com
c.com
[priority]
c.com
b.com
EOF
    XRAY_TIERS_FILE="$tiers_tmp"
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    PRIMARY_DOMAIN_MODE="adaptive"
    PRIMARY_ADAPTIVE_TOP_N=1
    select_primary_domain
  '
    [ "$status" -eq 0 ]
    [ "$output" = "b.com" ]
}

@test "build_domain_plan reuses domains only after one full cycle" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    SPIDER_MODE=true
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="a.com"
    build_domain_plan 7 false

    echo "total=${#DOMAIN_SELECTION_PLAN[@]}"
    unique_count=$(printf "%s\n" "${DOMAIN_SELECTION_PLAN[@]}" | sort -u | wc -l | tr -d " ")
    echo "unique=${unique_count}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "total=7" ]
    [ "${lines[1]}" = "unique=3" ]
}

@test "build_domain_plan avoids adjacent repeats when pool has multiple domains" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    SPIDER_MODE=true
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="a.com"
    build_domain_plan 8 true

    adjacent=0
    for ((i = 1; i < ${#DOMAIN_SELECTION_PLAN[@]}; i++)); do
      if [[ "${DOMAIN_SELECTION_PLAN[$i]}" == "${DOMAIN_SELECTION_PLAN[$((i - 1))]}" ]]; then
        adjacent=1
        break
      fi
    done

    echo "total=${#DOMAIN_SELECTION_PLAN[@]}"
    echo "adjacent=${adjacent}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "total=8" ]
    [ "${lines[1]}" = "adjacent=0" ]
}

@test "build_domain_plan pushes spares away from the primary family" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    summary_file=$(mktemp)
    trap "rm -f \"$summary_file\"" EXIT
    cat > "$summary_file" <<EOF
{"current_primary_family":"bluefam","operator_recommendation":"promote-spare","provider_family_stats":[]}
EOF
    MEASUREMENTS_SUMMARY_FILE="$summary_file"
    declare -gA DOMAIN_PROVIDER_FAMILIES=(
      ["a.com"]="bluefam"
      ["b.com"]="bluefam"
      ["c.com"]="greenfam"
    )
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    SPIDER_MODE=true
    PRIMARY_DOMAIN_MODE="pinned"
    PRIMARY_PIN_DOMAIN="a.com"
    load_provider_family_field_penalties
    build_domain_plan 3 true

    printf "first=%s\n" "${DOMAIN_SELECTION_PLAN[0]}"
    printf "second=%s\n" "${DOMAIN_SELECTION_PLAN[1]}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "first=a.com" ]
    [ "${lines[1]}" = "second=c.com" ]
}

@test "filter_quarantined_domains excludes domain in active cooldown" {
    run bash -eo pipefail -c '
    source ./lib.sh
    source ./config.sh
    log() { :; }
    DOMAIN_HEALTH_RANKING=true
    DOMAIN_QUARANTINE_FAIL_STREAK=3
    DOMAIN_QUARANTINE_COOLDOWN_MIN=120
    DOMAIN_HEALTH_FILE=$(mktemp)
    now_utc=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
    cat > "$DOMAIN_HEALTH_FILE" <<EOF
{"domains":{"a.com":{"fail_streak":0},"b.com":{"fail_streak":5,"last_fail":"${now_utc}"},"c.com":{"fail_streak":2,"last_fail":"${now_utc}"}}}
EOF
    AVAILABLE_DOMAINS=("a.com" "b.com" "c.com")
    filter_quarantined_domains
    printf "%s\n" "${AVAILABLE_DOMAINS[@]}"
  '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a.com" ]
    [ "${lines[1]}" = "c.com" ]
}
